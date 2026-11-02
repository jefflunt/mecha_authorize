# frozen_string_literal: true

require "yaml"

module MechaAuthorize
  class Matcher
    VALID_VERBS = %w[GET POST PUT PATCH DELETE HEAD OPTIONS *].freeze

    attr_reader :routes, :indexed_routes, :wildcard_routes, :colorization, :personas, :role_names

    def initialize(config_path_or_hash = nil, role_names = nil)
      @role_names = (role_names.nil? || role_names.empty? ? %i[public admin user_ui user_api] : role_names).map(&:to_sym)
      @indexed_routes = {}
      @wildcard_routes = []
      @raw_routes = []
      @colorization = {}
      @personas = {}

      if config_path_or_hash.is_a?(Hash)
        load_from_hash(config_path_or_hash)
      elsif config_path_or_hash
        load_from_file(config_path_or_hash)
      end
    end

    def load_from_file(path)
      raise "Authorization configuration file missing: #{path}" unless File.exist?(path)

      data = begin
        YAML.load_file(path)
      rescue => e
        raise "Invalid YAML syntax in #{path}: #{e.message}"
      end

      load_from_hash(data)
    end

    def load_from_hash(data)
      unless data.is_a?(Hash) && data.key?("routes") && data["routes"].is_a?(Array)
        raise "Authorization config must have a top-level 'routes' list"
      end

      @raw_routes = data["routes"]
      @indexed_routes = {}
      @wildcard_routes = []

      @raw_routes.each_with_index do |route, idx|
        validate_route_entry!(route, idx)
        register_route_entry(route)
      end

      if data["debug_colorization"].is_a?(Hash)
        @colorization = data["debug_colorization"].transform_keys(&:to_sym).transform_values { |v| v.to_s.sub(/^:/, "").to_sym }
      end

      @personas = parse_personas(data["personas"]) if data["personas"].is_a?(Hash)

      @indexed_routes.freeze
      @wildcard_routes.freeze
      @personas.freeze
      self
    end

    def valid_role?(role_name)
      return false if role_name.nil? || role_name.to_s.strip.empty?

      sym = role_name.to_s.strip.to_sym
      @role_names.include?(sym) || @personas.key?(sym)
    end

    def resolve_users_for_role(role_name, custom_resolvers = {})
      sym = role_name.to_s.strip.to_sym
      resolver = custom_resolvers[sym] || @personas.dig(sym, :user_resolver)
      return [] if resolver.nil?

      if resolver.respond_to?(:call)
        Array(resolver.call)
      elsif resolver.is_a?(String)
        evaluate_user_resolver_string(resolver)
      else
        []
      end
    end

    def format_user_entry(user)
      label = if user.respond_to?(:email) && user.email.present?
        user.email
      elsif user.respond_to?(:email_address) && user.email_address.present?
        user.email_address
      elsif user.respond_to?(:username) && user.username.present?
        user.username
      elsif user.respond_to?(:name) && user.name.present?
        user.name
      else
        user.to_s
      end

      if user.respond_to?(:id) && !user.id.nil?
        "#{label} (ID: #{user.id})"
      else
        label.to_s
      end
    end

    # Match incoming request by HTTP verb and path
    def match(verb, path, route_uri_pattern = nil)
      v = (verb || "GET").to_s.upcase
      clean_path = path.to_s.sub(/\(\.:format\)$/, "")

      # 1. Exact match [verb, path]
      rule = @indexed_routes[[v, clean_path]]
      return rule if rule

      # Fallback for HEAD -> GET
      if v == "HEAD" && (head_rule = @indexed_routes[["GET", clean_path]])
        return head_rule
      end

      # 2. Match [wildcard_verb "*", path]
      wildcard_verb_rule = @indexed_routes[["*", clean_path]]
      return wildcard_verb_rule if wildcard_verb_rule

      # 3. Path wildcards (e.g. /admin/*)
      @wildcard_routes.each do |w|
        next unless w[:verb] == "*" || w[:verb] == v || (v == "HEAD" && w[:verb] == "GET")

        pattern = w[:pattern]
        if File.fnmatch(pattern, clean_path) || (pattern.end_with?("/*") && clean_path == pattern.delete_suffix("/*"))
          return w[:rule]
        end
      end

      # 4. Rails dynamic route URI pattern fallback (e.g. /emails/:id/thread)
      if route_uri_pattern
        clean_pattern = route_uri_pattern.to_s.sub(/\(\.:format\)$/, "")
        rule = @indexed_routes[[v, clean_pattern]] || (v == "HEAD" && @indexed_routes[["GET", clean_pattern]]) || @indexed_routes[["*", clean_pattern]]
        return rule if rule
      end

      # 5. Regex parameterized fallback (matches paths like /auth/google_oauth2/callback to /auth/:provider/callback)
      regex_rule = match_by_pattern_regex(v, clean_path)
      return regex_rule if regex_rule

      nil
    end

    # Helper for static matching and route inspection: finds if a route specification matches
    def match_route_spec(verb, pattern)
      v = (verb || "GET").to_s.upcase
      clean_pattern = pattern.to_s.sub(/\(\.:format\)$/, "")

      # Exact match
      rule = @indexed_routes[[v, clean_pattern]] || @indexed_routes[["*", clean_pattern]]
      return rule if rule

      # Wildcard path check
      @wildcard_routes.each do |w|
        next unless w[:verb] == "*" || w[:verb] == v

        if File.fnmatch(w[:pattern], clean_pattern) || (w[:pattern].end_with?("/*") && clean_pattern.start_with?(w[:pattern].delete_suffix("/*")))
          return w[:rule]
        end
      end

      # Reverse regex matching: check if clean_pattern matches any indexed route pattern
      @indexed_routes.each do |(rule_verb, rule_pattern), r|
        next unless rule_verb == "*" || rule_verb == v
        next unless rule_pattern.include?(":")

        regex = pattern_to_regex(rule_pattern)
        return r if regex.match?(clean_pattern)
      end

      # Forward regex matching: check if any indexed pattern matches clean_pattern (e.g., /auth/:provider/callback vs /auth/google_oauth2)
      if clean_pattern.include?(":")
        spec_regex = pattern_to_regex(clean_pattern)
        @indexed_routes.each do |(rule_verb, rule_pattern), r|
          next unless rule_verb == "*" || rule_verb == v
          return r if spec_regex.match?(rule_pattern)
        end
      end

      nil
    end

    def all_rules
      @indexed_routes
    end

    private

    def validate_route_entry!(route, idx)
      unless route.is_a?(Hash)
        raise "Authorization route at index #{idx} is not a hash"
      end

      pattern = route["route_pattern"]
      unless pattern.is_a?(String) && !pattern.strip.empty? && pattern.start_with?("/")
        raise "Authorization route at index #{idx} must have a non-empty string starting with '/' for 'route_pattern'"
      end

      verbs = extract_verbs(route)
      if verbs.empty?
        raise "Authorization route '#{pattern}' at index #{idx} must explicitly define 'verb' or 'verbs'"
      end

      verbs.each do |verb|
        unless VALID_VERBS.include?(verb.upcase)
          raise "Authorization route '#{pattern}' key 'verb' has invalid HTTP verb '#{verb}'. Allowed verbs: #{VALID_VERBS.join(', ')}"
        end
      end

      @role_names.each do |role|
        val = route[role.to_s]
        unless val == true || val == false
          raise "Authorization route '#{pattern}' key '#{role}' must be a boolean (true or false), got #{val.inspect}"
        end
      end
    end

    def extract_verbs(route)
      if route.key?("verbs") && route["verbs"].is_a?(Array)
        route["verbs"].map { |v| v.to_s.strip.upcase }
      elsif route.key?("verb") && route["verb"].is_a?(String)
        [route["verb"].to_s.strip.upcase]
      else
        []
      end
    end

    def register_route_entry(route)
      pattern = route["route_pattern"]
      verbs = extract_verbs(route)

      rule = @role_names.each_with_object({}) do |role, h|
        h[role] = route[role.to_s]
      end.freeze

      verbs.each do |verb|
        key = [verb, pattern]
        @indexed_routes[key] = rule

        if pattern.include?("*")
          @wildcard_routes << {
            verb: verb,
            pattern: pattern,
            rule: rule
          }
        end
      end
    end

    def pattern_to_regex(pattern)
      segments = pattern.split("/", -1)
      regex_segments = segments.map do |seg|
        if seg.start_with?(":")
          "[^/]+"
        elsif seg.start_with?("*")
          ".*"
        else
          Regexp.escape(seg)
        end
      end
      Regexp.new("\\A#{regex_segments.join('/')}\\z")
    end

    def match_by_pattern_regex(verb, path)
      @indexed_routes.each do |(rule_verb, rule_pattern), rule|
        next unless rule_verb == "*" || rule_verb == verb || (verb == "HEAD" && rule_verb == "GET")
        next unless rule_pattern.include?(":")

        regex = pattern_to_regex(rule_pattern)
        return rule if regex.match?(path)
      end
      nil
    end

    def parse_personas(raw_personas)
      raw_personas.each_with_object({}) do |(role_key, cfg), h|
        sym = role_key.to_s.strip.to_sym
        if cfg.is_a?(Hash)
          h[sym] = {
            user_resolver: cfg["user_resolver"] || cfg[:user_resolver]
          }.freeze
        elsif cfg.is_a?(String)
          h[sym] = { user_resolver: cfg.strip }.freeze
        end
      end
    end

    def evaluate_user_resolver_string(expr)
      cleaned = expr.to_s.strip
      raise "Empty user_resolver expression" if cleaned.empty?

      parts = cleaned.split(".")
      const_name = parts.shift
      klass = Object.const_get(const_name)

      result = parts.reduce(klass) do |receiver, method_call|
        raise "Invalid method call '#{method_call}' in user_resolver '#{expr}'" unless method_call.match?(/\A[a-zA-Z_][a-zA-Z0-9_?!]*\z/)
        receiver.public_send(method_call)
      end

      result.respond_to?(:to_a) ? result.to_a : Array(result)
    end
  end
end
