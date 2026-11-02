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

  def test_context_for_and_controller_mecha_context_hook
    MechaAuthorize.configure do |config|
      config.config_path = @sample_config
      config.define_role(:public) { true }
      config.define_role(:admin) { |u, _r| u == :admin }
      config.define_role(:user_ui) { |u, _r| u == :ui }
      config.define_role(:user_api) { |u, _r| u == :api }
    end

    sample_routes = [
      { verb: "GET", path: "/", controller: "PublicController", action: "index" },
      { verb: "GET", path: "/home", controller: "HomeController", action: "index" },
      { verb: "DELETE", path: "/admin/users/:id", controller: "Admin::UsersController", action: "destroy" },
      { verb: "GET", path: "/unmapped/secret", controller: "SecretsController", action: "show" }
    ]

    # 1. Controller#action introspection
    destroy_ctx = MechaAuthorize.context_for("Admin::UsersController#destroy", routes: sample_routes)
    assert_equal :admin, destroy_ctx[:required_persona]
    assert_equal [:admin], destroy_ctx[:allowed_personas]
    assert_equal "/admin/users/:id", destroy_ctx[:route]
    assert_equal "DELETE", destroy_ctx[:verb]
    assert_equal :authorized, destroy_ctx[:status]
    refute destroy_ctx[:public]

    # 2. Public route introspection
    root_ctx = MechaAuthorize.context_for("GET /", routes: sample_routes)
    assert_equal :public, root_ctx[:required_persona]
    assert_equal :public, root_ctx[:status]
    assert root_ctx[:public]

    # 3. Unmapped route fails closed (:denied_by_default)
    unmapped_ctx = MechaAuthorize.context_for("SecretsController#show", routes: sample_routes)
    assert_nil unmapped_ctx[:required_persona]
    assert_empty unmapped_ctx[:allowed_personas]
    assert_equal :denied_by_default, unmapped_ctx[:status]

    # 4. Controller class & instance #mecha_context hook
    dummy_ctrl_base = Class.new do
      def self.before_action(*); end
      include MechaAuthorize::Controller
    end

    admin_ctrl = Class.new(dummy_ctrl_base) do
      def self.name
        "Admin::UsersController"
      end

      attr_accessor :action_name
    end

    ctrl_ctx = admin_ctrl.mecha_context(nil, routes: sample_routes)
    assert_equal "Admin::UsersController", ctrl_ctx[:controller]
    assert ctrl_ctx[:closed_by_default]
    assert_equal :admin, ctrl_ctx[:actions]["destroy"][:required_persona]

    instance = admin_ctrl.new
    instance.action_name = "destroy"
    inst_ctx = instance.mecha_context(nil, routes: sample_routes)
    assert_equal :admin, inst_ctx[:required_persona]
    assert_equal "/admin/users/:id", inst_ctx[:route]
  end
end
