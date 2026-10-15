# frozen_string_literal: true

module MechaAuthorize
  module Auditor
    class Static
      Result = Struct.new(
        :mapped_routes,
        :unmapped_routes,
        :dead_rules,
        :engine_warnings,
        keyword_init: true
      ) do
        def success?
          dead_rules.empty? && engine_warnings.empty?
        end
      end

      def initialize(matcher = MechaAuthorize.matcher)
        @matcher = matcher
      end

      def audit
        rails_routes = collect_all_routes
        mapped = []
        unmapped = []
        matched_rules = Set.new

        rails_routes.each do |r|
          rule = @matcher.match_route_spec(r[:verb], r[:path])

          if rule
            mapped << r.merge(rule: rule)
            matched_rules << rule
          else
            unmapped << r
          end
        end

        # Check for dead/stale rules in mecha_authorize.yml
        # A rule is dead if it does not match any actual Rails route and is not a wildcard
        dead_rules = []
        @matcher.all_rules.each do |(verb, pattern), rule|
          next if pattern.include?("*") # Wildcards cover dynamic/future paths

          # Check if any route matched this specific pattern and verb
          matched = rails_routes.any? do |r|
            (verb == "*" || r[:verb] == "*" || r[:verb] == verb) &&
              route_matches_pattern?(r[:path], pattern)
          end

          dead_rules << { verb: verb, pattern: pattern, rule: rule } unless matched
        end

        # Check mounted engines for authorization gate coverage
        engine_warnings = audit_mounted_engines

        Result.new(
          mapped_routes: mapped,
          unmapped_routes: unmapped,
          dead_rules: dead_rules,
          engine_warnings: engine_warnings
        )
      end

      private

      def route_matches_pattern?(route_path, config_pattern)
        clean_route = route_path.sub(/\(\.:format\)$/, "")
        clean_config = config_pattern.sub(/\(\.:format\)$/, "")

        return true if clean_route == clean_config

        # Check parameterized segment matching
        route_regex = pattern_to_regex(clean_route)
        config_regex = pattern_to_regex(clean_config)

        route_regex.match?(clean_config) || config_regex.match?(clean_route)
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

      def collect_all_routes
        routes = Rails.application.routes.routes.map do |r|
          ActionDispatch::Routing::RouteWrapper.new(r)
        end.reject(&:internal?)

        all = []

        routes.each do |r|
          if r.engine?
            engine_routes = r.rack_app.routes
            engine_routes = engine_routes.routes if engine_routes.is_a?(ActionDispatch::Routing::RouteSet)
            clean_mount = r.path.sub("(.:format)", "").sub("/*path", "").sub("/*filename", "").chomp("/")

            engine_routes.map { |er| ActionDispatch::Routing::RouteWrapper.new(er) }.reject(&:internal?).each do |er|
              verb = extract_verb(er)
              full_path = "#{clean_mount}#{er.path}".sub("(.:format)", "")
              all << { verb: verb, path: full_path, engine: r.rack_app.name }
            end
          else
            verb = extract_verb(r)
            all << { verb: verb, path: r.path.sub("(.:format)", ""), engine: nil }
          end
        end

        all
      end

      def extract_verb(route_wrapper)
        raw_verb = route_wrapper.verb.to_s
        raw_verb.empty? ? "*" : raw_verb.upcase
      end

      def audit_mounted_engines
        warnings = []
        routes = Rails.application.routes.routes.select { |r| r.app.engine? if r.app.respond_to?(:engine?) }

        routes.each do |route|
          rack_app = route.app.rack_app
          engine_name = rack_app.name || rack_app.to_s

          # Check if engine's base controller inherits ApplicationController or includes MechaAuthorize
          base_controller_name = "#{engine_name}::ApplicationController"
          base_controller = base_controller_name.safe_constantize

          if base_controller
            inherits_app_ctrl = base_controller < ::ApplicationController
            includes_mecha_auth = base_controller.ancestors.include?(MechaAuthorize::Controller)

            unless inherits_app_ctrl || includes_mecha_auth
              warnings << "Mounted engine #{engine_name} at #{route.path.spec} base controller #{base_controller_name} does not inherit ApplicationController or include MechaAuthorize::Controller."
            end
          end
        end

        warnings
      end
    end
  end
end
