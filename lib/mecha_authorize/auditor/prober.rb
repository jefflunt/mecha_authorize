# frozen_string_literal: true

module MechaAuthorize
  module Auditor
    class Prober
      ProbeFailure = Struct.new(:route, :persona, :expected_status, :actual_status, :message, keyword_init: true)

      Result = Struct.new(:probed_count, :failures, keyword_init: true) do
        def success?
          failures.empty?
        end
      end

      DEFAULT_PARAM_SUBSTITUTIONS = {
        ":id" => "1",
        ":card_id" => "card-1",
        ":table_id" => "table-1",
        ":provider" => "google_oauth2",
        ":application_id" => "app-1",
        ":queue_id" => "queue-1",
        ":filename" => "test.png",
        ":path" => "test"
      }.freeze

      def initialize(integration_session = nil, matcher = MechaAuthorize.matcher)
        @session = integration_session
        @matcher = matcher
      end

      def probe_all_routes(persona_generator)
        failures = []
        probed_count = 0

        routes = collect_prober_routes

        routes.each do |route_info|
          route_res = probe_route(route_info, persona_generator)
          probed_count += route_res.probed_count
          failures.concat(route_res.failures)
        end

        Result.new(probed_count: probed_count, failures: failures)
      end

      def probe_route(route_info, persona_generator)
        failures = []
        probed_count = 0

        verb = route_info[:verb]
        raw_path = route_info[:path]
        path = substitute_params(raw_path)
        rule = @matcher.match(verb, path, raw_path)

        personas = persona_generator.respond_to?(:call) ? persona_generator.call : persona_generator

        personas.each do |persona_name, user_setup|
          probed_count += 1
          expected_status = calculate_expected_status(raw_path, rule, persona_name)

          extra_headers = user_setup.call(@session) || {}

          actual_status = dispatch_probe_request(verb, path, extra_headers)

          unless status_matches?(actual_status, expected_status)
            failures << ProbeFailure.new(
              route: "#{verb} #{raw_path} (#{path})",
              persona: persona_name,
              expected_status: expected_status,
              actual_status: actual_status,
              message: "Expected HTTP #{expected_status} but received HTTP #{actual_status}"
            )
          end
        end

        Result.new(probed_count: probed_count, failures: failures)
      end

      def substitute_params(path)
        result = path.dup
        DEFAULT_PARAM_SUBSTITUTIONS.each do |param, val|
          result.gsub!(param, val)
        end
        # Generic fallback for any remaining :param
        result.gsub!(/:[a-zA-Z_]+/, "1")
        result
      end

      def collect_prober_routes
        self.class.collect_prober_routes
      end

      def self.collect_prober_routes
        return [] unless defined?(Rails) && Rails.respond_to?(:application) && Rails.application

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
              verb = er.verb.to_s.empty? ? "*" : er.verb.to_s.upcase
              full_path = "#{clean_mount}#{er.path}".sub("(.:format)", "")
              all << { verb: verb, path: full_path }
            end
          else
            verb = r.verb.to_s.empty? ? "*" : r.verb.to_s.upcase
            all << { verb: verb, path: r.path.sub("(.:format)", "") }
          end
        end

        all.uniq { |r| [r[:verb], r[:path]] }
      end

      private

      def calculate_expected_status(raw_path, rule, persona_name)
        sentinel = MechaAuthorize.configuration.probe_status
        is_api = raw_path.start_with?("/api/")

        return 404 if rule.nil?

        if rule[:public]
          return sentinel
        end

        case persona_name
        when :anonymous
          is_api ? [400, 401, 404] : 404
        when :admin
          rule[:admin] ? sentinel : (is_api ? [400, 401, 403, 404] : 404)
        when :user_ui
          (rule[:user_ui] && !is_api) ? sentinel : (is_api ? [400, 401, 403, 404] : 404)
        when :user_api
          rule[:user_api] ? sentinel : (is_api ? [400, 401, 403, 404] : 404)
        when :restricted
          is_api ? [400, 401, 403, 404] : 404
        else
          404
        end
      end

      def status_matches?(actual_status, expected_status)
        if expected_status.is_a?(Array)
          expected_status.include?(actual_status)
        else
          actual_status == expected_status
        end
      end

      def dispatch_probe_request(verb, path, extra_headers = {})
        headers = { MechaAuthorize.configuration.probe_header => "1" }.merge(extra_headers)

        case verb.to_s.upcase
        when "GET", "*"
          @session.get path, headers: headers
        when "POST"
          @session.post path, headers: headers
        when "PATCH"
          @session.patch path, headers: headers
        when "PUT"
          @session.put path, headers: headers
        when "DELETE"
          @session.delete path, headers: headers
        when "HEAD"
          @session.head path, headers: headers
        else
          @session.get path, headers: headers
        end

        @session.response.status
      rescue ActionController::RoutingError
        404
      end
    end
  end
end
