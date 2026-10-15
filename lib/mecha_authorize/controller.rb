# frozen_string_literal: true

require "active_support/concern"

module MechaAuthorize
  module Controller
    extend ActiveSupport::Concern

    included do
      before_action :authorize_route!
    end

    class_methods do
      def authorization_routes
        if defined?(@authorization_routes) && !@authorization_routes.nil?
          @authorization_routes
        elsif superclass.respond_to?(:authorization_routes) && superclass != ActionController::Base
          superclass.authorization_routes
        elsif defined?(AUTHORIZATION_ROUTES)
          AUTHORIZATION_ROUTES
        else
          MechaAuthorize.matcher&.all_rules || {}
        end
      end

      def authorization_routes=(routes)
        @authorization_routes = routes
      end
    end

    private

    def authorize_route!
      verb = extract_request_verb
      path = request.path
      route_uri_pattern = request.respond_to?(:route_uri_pattern) ? request.route_uri_pattern : nil

      # If custom authorization_routes are set on the controller class (e.g. In isolated unit tests),
      # evaluate against that custom dictionary; otherwise use the global MechaAuthorize.matcher.
      custom_routes = self.class.authorization_routes
      rule = if custom_routes && custom_routes != AUTHORIZATION_ROUTES && custom_routes != MechaAuthorize.matcher&.all_rules
        match_custom_routes(verb, path, route_uri_pattern, custom_routes)
      else
        MechaAuthorize.matcher.match(verb, path, route_uri_pattern)
      end

      # 1. Closed-by-default: If no rule matches, deny access
      if rule.nil?
        render_unauthorized
        return
      end

      # 2. Public bypass
      if rule[:public]
        if probe_request?
          head MechaAuthorize.configuration.probe_status
          return
        end
        return
      end

      # 3. Authentication requirement for non-public routes
      unless logged_in?
        render_unauthorized
        return
      end

      # 4. Check permissions
      has_access = check_role_access(rule)

      unless has_access
        render_unauthorized
        return
      end

      # 5. Early return on probe requests with sentinel status
      if probe_request?
        head MechaAuthorize.configuration.probe_status and return
      end
    end

    def extract_request_verb
      if request.respond_to?(:request_method) && request.request_method.present?
        request.request_method.to_s.upcase
      elsif request.respond_to?(:raw_request_method) && request.raw_request_method.present?
        request.raw_request_method.to_s.upcase
      else
        begin
          v = request.method
          v.is_a?(String) ? v.upcase : "GET"
        rescue ArgumentError
          "GET"
        end
      end
    end

    def probe_request?
      header_name = MechaAuthorize.configuration.probe_header
      val = nil
      if request.respond_to?(:headers) && request.headers
        val = request.headers[header_name]
      end
      if val.nil? && request.respond_to?(:get_header)
        val = request.get_header("HTTP_#{header_name.upcase.tr('-', '_')}")
      end
      val == "1" || val == "true"
    end

    def check_role_access(rule)
      user = current_user
      roles = MechaAuthorize.configuration.roles

      roles.any? do |role_name, resolver|
        next false if role_name == :public
        rule[role_name] && resolver.call(user, request)
      end
    end

    def render_unauthorized
      MechaAuthorize.configuration.on_unauthorized.call(self)
    end

    def current_user
      nil
    end

    def logged_in?
      respond_to?(:current_user, true) && !current_user.nil?
    end

    def match_custom_routes(verb, path, route_uri_pattern, routes_hash)
      # Check compound key [verb, path]
      key = [verb.to_s.upcase, path]
      return routes_hash[key] if routes_hash.key?(key)

      # Check wildcard verb ["*", path]
      wildcard_verb_key = ["*", path]
      return routes_hash[wildcard_verb_key] if routes_hash.key?(wildcard_verb_key)

      # Check plain path key (legacy backward-compatibility for mocks)
      return routes_hash[path] if routes_hash.key?(path)

      # Check wildcards
      routes_hash.each do |k, v|
        pattern = k.is_a?(Array) ? k[1] : k
        rule_verb = k.is_a?(Array) ? k[0] : "*"

        next unless rule_verb == "*" || rule_verb == verb.to_s.upcase

        if pattern.include?("*") && (
          File.fnmatch(pattern, path) || (pattern.end_with?("/*") && path == pattern.delete_suffix("/*"))
        )
          return v
        end
      end

      # Dynamic pattern fallback
      if route_uri_pattern
        clean_pat = route_uri_pattern.sub(/\(\.:format\)$/, "")
        return routes_hash[[verb.to_s.upcase, clean_pat]] if routes_hash.key?([verb.to_s.upcase, clean_pat])
        return routes_hash[["*", clean_pat]] if routes_hash.key?([clean_pat])
        return routes_hash[clean_pat] if routes_hash.key?(clean_pat)
        return routes_hash[route_uri_pattern] if routes_hash.key?(route_uri_pattern)
      end

      nil
    end
  end
end
