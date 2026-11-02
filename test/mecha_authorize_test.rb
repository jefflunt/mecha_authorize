# frozen_string_literal: true

require "test_helper"
require "active_support/core_ext/object/blank"

class MechaAuthorizeTest < Minitest::Test
  def setup
    MechaAuthorize.reset_configuration!
    @sample_config = {
      "debug_colorization" => {
        "public" => ":green",
        "admin" => ":light_red",
        "user_ui" => ":light_purple",
        "user_api" => ":light_cyan",
        "none" => ":dark_grey"
      },
      "routes" => [
        {
          "route_pattern" => "/",
          "verb" => "GET",
          "public" => true,
          "admin" => false,
          "user_ui" => false,
          "user_api" => false
        },
        {
          "route_pattern" => "/home",
          "verb" => "GET",
          "public" => false,
          "admin" => true,
          "user_ui" => true,
          "user_api" => false
        },
        {
          "route_pattern" => "/admin/*",
          "verb" => "*",
          "public" => false,
          "admin" => true,
          "user_ui" => false,
          "user_api" => false
        },
        {
          "route_pattern" => "/api/v1/emails/:id",
          "verbs" => ["GET", "PATCH", "DELETE"],
          "public" => false,
          "admin" => false,
          "user_ui" => false,
          "user_api" => true
        }
      ]
    }
  end

  def teardown
    MechaAuthorize.reset_configuration!
  end

  def test_version_is_defined
    refute_nil MechaAuthorize::VERSION
    assert_equal MechaAuthorize::VERSION, MechaAuthorize::Version
  end

  def test_matcher_loads_and_matches_exact_wildcard_and_parameterized_routes
    matcher = MechaAuthorize::Matcher.new(@sample_config)

    root_rule = matcher.match("GET", "/")
    assert_equal({ public: true, admin: false, user_ui: false, user_api: false }, root_rule)

    # HEAD falls back to GET
    head_rule = matcher.match("HEAD", "/")
    assert_equal root_rule, head_rule

    # Wrong verb returns nil (closed-by-default)
    assert_nil matcher.match("POST", "/")

    # Wildcard route matching
    admin_rule = matcher.match("POST", "/admin/users")
    assert_equal({ public: false, admin: true, user_ui: false, user_api: false }, admin_rule)

    # Parameterized route matching
    api_rule = matcher.match("PATCH", "/api/v1/emails/42")
    assert_equal({ public: false, admin: false, user_ui: false, user_api: true }, api_rule)
    assert_nil matcher.match("POST", "/api/v1/emails/42")

    # Unmapped route returns nil
    assert_nil matcher.match("GET", "/unmapped")
  end

  def test_matcher_validates_schema
    assert_raises(RuntimeError) do
      MechaAuthorize::Matcher.new({ "other" => [] })
    end

    assert_raises(RuntimeError) do
      MechaAuthorize::Matcher.new({ "routes" => ["not-a-hash"] })
    end

    assert_raises(RuntimeError) do
      MechaAuthorize::Matcher.new({
        "routes" => [{ "route_pattern" => "invalid_no_slash", "verb" => "GET", "public" => true, "admin" => false, "user_ui" => false, "user_api" => false }]
      })
    end

    assert_raises(RuntimeError) do
      MechaAuthorize::Matcher.new({
        "routes" => [{ "route_pattern" => "/test", "verb" => "INVALID_VERB", "public" => true, "admin" => false, "user_ui" => false, "user_api" => false }]
      })
    end

    assert_raises(RuntimeError) do
      MechaAuthorize::Matcher.new({
        "routes" => [{ "route_pattern" => "/test", "verb" => "GET", "public" => "yes", "admin" => false, "user_ui" => false, "user_api" => false }]
      })
    end
  end

  def test_configuration_and_role_definitions
    MechaAuthorize.configure do |config|
      config.config_path = @sample_config
      config.define_role(:public) { |_u, _r| true }
      config.define_role(:admin) { |u, _r| u == :admin_user }
      config.define_role(:user_ui) { |u, _r| u == :ui_user }
      config.define_role(:user_api) { |u, _r| u == :api_user }
    end

    assert_equal %i[public admin user_ui user_api], MechaAuthorize.configuration.role_names
    assert_equal 251, MechaAuthorize.configuration.probe_status
    assert_equal "X-Mecha-Authorize-Probe", MechaAuthorize.configuration.probe_header
    refute_nil MechaAuthorize.matcher.match("GET", "/home")
  end

  def test_prober_substitutes_params
    matcher = MechaAuthorize::Matcher.new(@sample_config)
    prober = MechaAuthorize::Auditor::Prober.new(nil, matcher)

    assert_equal "/api/v1/emails/1", prober.substitute_params("/api/v1/emails/:id")
    assert_equal "/auth/google_oauth2/callback", prober.substitute_params("/auth/:provider/callback")
    assert_equal "/custom/1/items", prober.substitute_params("/custom/:custom_param/items")
  end

  def test_mecha_authorize_role_user_listing_and_validation
    require "rake"
    Rake::Task.clear
    Rake::Task.define_task(:environment)
    load File.expand_path("../lib/tasks/mecha_authorize.rake", __dir__)

    user_struct = Struct.new(:id, :email, keyword_init: true)
    sample_users = [
      user_struct.new(id: 1, email: "alice@example.com"),
      user_struct.new(id: 4, email: "bob@example.com"),
      user_struct.new(id: 12, email: "carol@example.com")
    ]

    Object.const_set(:FakeUserForRoleTest, Class.new do
      define_singleton_method(:admins) { sample_users }
      define_singleton_method(:none_scope) { [] }
    end)

    config_with_personas = @sample_config.merge(
      "personas" => {
        "admin" => { "user_resolver" => "FakeUserForRoleTest.admins" },
        "user_ui" => { "user_resolver" => "FakeUserForRoleTest.none_scope" }
      }
    )

    MechaAuthorize.configure do |config|
      config.config_path = config_with_personas
    end

    fake_route_struct = Struct.new(:verb, :path, :controller, :action, :internal, :engine, keyword_init: true) do
      def internal?
        !!internal
      end

      def engine?
        !!engine
      end
    end

    fake_routes = [
      fake_route_struct.new(verb: "GET", path: "/home(.:format)", controller: "home", action: "index"),
      fake_route_struct.new(verb: "POST", path: "/admin/users/:id/suspend(.:format)", controller: "admin/users", action: "suspend"),
      fake_route_struct.new(verb: "GET", path: "/", controller: "public", action: "index")
    ]

    had_rails = Object.const_defined?(:Rails)
    orig_rails = Object.const_get(:Rails) if had_rails
    had_ad = Object.const_defined?(:ActionDispatch)
    orig_ad = Object.const_get(:ActionDispatch) if had_ad

    begin
      routes_holder = Struct.new(:routes)
      fake_rails = Module.new do
        define_singleton_method(:application) do
          route_set = routes_holder.new(fake_routes)
          routes_holder.new(route_set)
        end
      end
      Object.send(:remove_const, :Rails) if had_rails
      Object.const_set(:Rails, fake_rails)

      fake_ad = Module.new do
        routing = Module.new do
          wrapper = Class.new do
            def initialize(r)
              @r = r
            end

            def internal?
              @r.internal?
            end

            def engine?
              @r.engine?
            end

            def verb
              @r.verb
            end

            def path
              @r.path
            end

            def controller
              @r.controller
            end

            def action
              @r.action
            end
          end
          const_set(:RouteWrapper, wrapper)
        end
        const_set(:Routing, routing)
      end
      Object.send(:remove_const, :ActionDispatch) if had_ad
      Object.const_set(:ActionDispatch, fake_ad)

      # 1. Valid role with users prints users and routes authorized for that role
      out, _err = capture_io do
        Rake::Task["mecha_authorize"].reenable
        Rake::Task["mecha_authorize"].invoke("admin")
      end

      assert_includes out, "Users in role 'admin' (3 found):"
      assert_includes out, "- alice@example.com (ID: 1)"
      assert_includes out, "- bob@example.com (ID: 4)"
      assert_includes out, "- carol@example.com (ID: 12)"
      assert_includes out, "Routes authorized for 'admin':"
      assert_includes out, "/admin/users/:id/suspend"
      assert_includes out, "=> Admin::UsersController#suspend"
      assert_includes out, "/home"
      refute_includes out, "PublicController#index"

      # 2. Valid role with 0 users prints NO USERS FOUND notice
      out, _err = capture_io do
        Rake::Task["mecha_authorize"].reenable
        Rake::Task["mecha_authorize"].invoke("user_ui")
      end
      assert_includes out, "NO USERS FOUND IN ROLE 'user_ui'"
      assert_includes out, "Routes authorized for 'user_ui':"

      # 3. Unknown role prints error and exits non-zero
      err = nil
      out, _err = capture_io do
        Rake::Task["mecha_authorize"].reenable
        err = assert_raises(SystemExit) do
          Rake::Task["mecha_authorize"].invoke("superadmin")
        end
      end
      assert_equal 1, err.status
      assert_includes out, "does not exist in config/mecha_authorize.yml"
    ensure
      Object.send(:remove_const, :FakeUserForRoleTest) if Object.const_defined?(:FakeUserForRoleTest)
      Object.send(:remove_const, :Rails) if Object.const_defined?(:Rails)
      Object.const_set(:Rails, orig_rails) if had_rails
      Object.send(:remove_const, :ActionDispatch) if Object.const_defined?(:ActionDispatch)
      Object.const_set(:ActionDispatch, orig_ad) if had_ad
    end
  end
end
