# frozen_string_literal: true

module MechaAuthorize
  class Configuration
    attr_accessor :config_path,
                  :probe_header,
                  :probe_status,
                  :debug_colorization,
                  :on_unauthorized,
                  :test_personas,
                  :test_setup,
                  :test_teardown

    def initialize
      @config_path = defined?(Rails) && Rails.respond_to?(:root) && Rails.root ? Rails.root.join("config/mecha_authorize.yml") : "config/mecha_authorize.yml"
      @probe_header = "X-Mecha-Authorize-Probe"
      @probe_status = 251 # Special sentinel HTTP status (251 Verified)
      @roles = {}
      @user_resolvers = {}
      @debug_colorization = {
        public: :green,
        admin: :light_red,
        user_ui: :light_purple,
        user_api: :light_cyan,
        none: :dark_grey
      }
      @on_unauthorized = ->(controller) { controller.send(:render_404) }
      @test_personas = nil
      @test_setup = nil
      @test_teardown = nil
    end

    def define_role(name, user_resolver: nil, &block)
      role_sym = name.to_sym
      @roles[role_sym] = block
      @user_resolvers[role_sym] = user_resolver if user_resolver
    end

    def define_user_resolver(name, resolver = nil, &block)
      @user_resolvers[name.to_sym] = resolver || block
    end

    def user_resolvers
      @user_resolvers
    end

    def roles
      @roles
    end

    def role_names
      @roles.keys
    end

    def configure_test_matrix(personas: nil, setup: nil, teardown: nil)
      @test_personas = personas if personas
      @test_setup = setup if setup
      @test_teardown = teardown if teardown
    end
  end
end
