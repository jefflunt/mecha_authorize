# frozen_string_literal: true

require "active_support/core_ext/object/blank"
require "active_support/core_ext/string/inflections"

module MechaAuthorize
  module Context
    class << self
      def for_target(target = nil, matcher: MechaAuthorize.matcher, routes: nil)
        route_list = routes || collect_routes

        if target.nil? || target.to_s.strip.empty? || target.to_s.strip == "all"
          return full_context(matcher, route_list)
        end

        if target.is_a?(Class) || target.is_a?(Module)
          return for_controller(target.name.to_s, matcher: matcher, routes: route_list)
        end

        str = target.to_s.strip

        # 1. Explicit "VERB /path" or "/path"
        if str.start_with?("/") || str.match?(/\A(GET|POST|PUT|PATCH|DELETE|HEAD|OPTIONS|\*)\s+\//i)
          verb, path = parse_verb_and_path(str)
          route_meta = route_list.find { |r| (r[:verb] == verb || r[:verb] == "*") && r[:path] == path }
          return build_route_context(
            verb: verb,
            path: path,
            controller: route_meta&.[](:controller),
            action: route_meta&.[](:action),
            matcher: matcher
          )
        end

        # 2. "ControllerClass#action" or "controller_path#action"
        if str.include?("#")
          ctrl_part, action_name = str.split("#", 2)
          ctrl_class_name = normalize_controller_name(ctrl_part)
          return for_controller_action(ctrl_class_name, action_name, matcher: matcher, routes: route_list)
        end

        # 3. Controller class name
        ctrl_class_name = normalize_controller_name(str)
        for_controller(ctrl_class_name, matcher: matcher, routes: route_list)
      end

      private

      def full_context(matcher, route_list)
        {
          closed_by_default: true,
          roles: matcher.nil? ? [] : MechaAuthorize.configuration.role_names,
          routes: route_list.map do |r|
            build_route_context(
              verb: r[:verb],
              path: r[:path],
              controller: r[:controller],
              action: r[:action],
              matcher: matcher
            )
          end
        }
      end

      def for_controller(ctrl_class_name, matcher:, routes:)
        matching = routes.select { |r| r[:controller] == ctrl_class_name }
        actions = {}

        matching.each do |r|
          actions[r[:action]] = build_route_context(
            verb: r[:verb],
            path: r[:path],
            controller: ctrl_class_name,
            action: r[:action],
            matcher: matcher
          )
        end

        {
          controller: ctrl_class_name,
          closed_by_default: true,
          actions: actions
        }
      end

      def for_controller_action(ctrl_class_name, action_name, matcher:, routes:)
        matching = routes.select { |r| r[:controller] == ctrl_class_name && r[:action] == action_name.to_s }

        if matching.empty?
          return {
            controller: ctrl_class_name,
            action: action_name.to_s,
            route: nil,
            verb: nil,
            required_persona: nil,
            allowed_personas: [],
            public: false,
            status: :unrouted,
            permissions: {}
          }
        end

        first = matching.first
        build_route_context(
          verb: first[:verb],
          path: first[:path],
          controller: ctrl_class_name,
          action: action_name.to_s,
          matcher: matcher
        )
      end

      def build_route_context(verb:, path:, controller:, action:, matcher:)
        rule = matcher&.match_route_spec(verb, path)
        allowed = if rule
          rule.select { |_k, v| v == true }.keys
        else
          []
        end

        status = if rule.nil? || allowed.empty?
          :denied_by_default
        elsif rule[:public]
          :public
        else
          :authorized
        end

        {
          controller: controller,
          action: action,
          route: path,
          verb: verb,
          required_persona: allowed.first,
          allowed_personas: allowed,
          public: !!(rule && rule[:public]),
          status: status,
          permissions: rule || {}
        }
      end

      def parse_verb_and_path(str)
        if str.include?(" ")
          v, p = str.split(/\s+/, 2)
          [v.upcase, p.strip]
        else
          ["GET", str]
        end
      end

      def normalize_controller_name(raw)
        cleaned = raw.to_s.strip
        return cleaned if cleaned.end_with?("Controller")

        "#{cleaned.camelize}Controller"
      end

      def collect_routes
        return [] unless defined?(Rails) && Rails.respond_to?(:application) && Rails.application

        routes = Rails.application.routes.routes.map do |r|
          ActionDispatch::Routing::RouteWrapper.new(r)
        end.reject(&:internal?)

        all = []
        routes.each do |r|
          if r.engine?
            engine_routes = r.rack_app.routes
            engine_routes = engine_routes.routes if defined?(ActionDispatch::Routing::RouteSet) && engine_routes.is_a?(ActionDispatch::Routing::RouteSet)
            clean_mount = r.path.sub("(.:format)", "").sub("/*path", "").sub("/*filename", "").chomp("/")

            engine_routes.map { |er| ActionDispatch::Routing::RouteWrapper.new(er) }.reject(&:internal?).each do |er|
              verb = er.verb.to_s.empty? ? "*" : er.verb.to_s.upcase
              full_path = "#{clean_mount}#{er.path}".sub("(.:format)", "")
              ctrl = er.respond_to?(:controller) && er.controller.present? ? "#{er.controller.camelize}Controller" : nil
              act = er.respond_to?(:action) ? er.action.presence : nil
              all << { verb: verb, path: full_path, controller: ctrl, action: act }
            end
          else
            verb = r.verb.to_s.empty? ? "*" : r.verb.to_s.upcase
            ctrl = r.respond_to?(:controller) && r.controller.present? ? "#{r.controller.camelize}Controller" : nil
            act = r.respond_to?(:action) ? r.action.presence : nil
            all << { verb: verb, path: r.path.sub("(.:format)", ""), controller: ctrl, action: act }
          end
        end

        all
      end
    end
  end
end
