# frozen_string_literal: true

require_relative "mecha_authorize/version"
require_relative "mecha_authorize/configuration"
require_relative "mecha_authorize/matcher"
require_relative "mecha_authorize/controller"
require_relative "mecha_authorize/auditor/static"
require_relative "mecha_authorize/auditor/prober"
require_relative "mecha_authorize/railtie" if defined?(Rails::Railtie)

module MechaAuthorize
  class << self
    def configuration
      @configuration ||= Configuration.new
    end

    def configure
      yield(configuration) if block_given?
      reload!
    end

    def reset_configuration!
      @configuration = Configuration.new
      @matcher = nil
    end

    def matcher
      @matcher ||= Matcher.new(configuration.config_path, configuration.role_names)
    end

    def reload!
      @matcher = Matcher.new(configuration.config_path, configuration.role_names)
    end
  end
end
