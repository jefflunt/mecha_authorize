# frozen_string_literal: true

unless defined?(ActionDispatch::IntegrationTest)
  app_test_helper = File.join(Dir.pwd, "test/test_helper.rb")
  require app_test_helper if File.exist?(app_test_helper)
end
require "mecha_authorize"

module MechaAuthorize
  class MatrixTest < ActionDispatch::IntegrationTest
    setup do
      if MechaAuthorize.configuration.test_setup
        instance_exec(&MechaAuthorize.configuration.test_setup)
      end
    end

    teardown do
      if MechaAuthorize.configuration.test_teardown
        instance_exec(&MechaAuthorize.configuration.test_teardown)
      end
    end

    test "static route authorization audit passes with zero dead rules and zero engine bypasses" do
      result = MechaAuthorize::Auditor::Static.new.audit

      assert_empty result.dead_rules, "Found dead/stale rules in mecha_authorize.yml: #{result.dead_rules.inspect}"
      assert_empty result.engine_warnings, "Found engine bypass warnings: #{result.engine_warnings.inspect}"
      assert result.mapped_routes.any?, "Expected routes to be mapped to authorization rules"
    end

    test "unmapped routes strictly return 404 for all personas" do
      get "/unmapped_nonexistent_test_route", headers: { MechaAuthorize.configuration.probe_header => "1" }
      assert_response :not_found

      get "/unmapped_nonexistent_test_route"
      assert_response :not_found
    end

    test "wrong HTTP verb strictly returns 404 closed-by-default" do
      delete "/login", headers: { MechaAuthorize.configuration.probe_header => "1" }
      assert_response :not_found
    end

    def self.define_route_matrix_tests!
      return if @route_matrix_tests_defined

      routes = MechaAuthorize::Auditor::Prober.collect_prober_routes
      return if routes.empty?

      @route_matrix_tests_defined = true

      routes.each do |route_info|
        verb = route_info[:verb]
        raw_path = route_info[:path]

        test "behavioral persona matrix probe for #{verb} #{raw_path}" do
          personas_proc = MechaAuthorize.configuration.test_personas
          assert_not_nil personas_proc, "MechaAuthorize.configuration.test_personas must be configured for behavioral matrix testing"

          prober = MechaAuthorize::Auditor::Prober.new(self)
          personas = instance_exec(&personas_proc)
          result = prober.probe_route(route_info, personas)

          assert result.success?, "Prober failed for #{verb} #{raw_path}:\n" +
            result.failures.map { |f| "  - #{f.route} [#{f.persona}]: #{f.message}" }.join("\n")
        end
      end
    end

    define_route_matrix_tests!
  end
end
