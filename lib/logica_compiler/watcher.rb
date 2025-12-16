# frozen_string_literal: true

require_relative "deps/sleeper"

module LogicaCompiler
  class Watcher
    DEFAULT_CONFIG_PATH = "logica/config.yml"
    PROGRAMS_DIR = "logica/programs"

    def self.start!(config_path: DEFAULT_CONFIG_PATH, **kwargs)
      new(config_path:, **kwargs).start!
    end

    def initialize(
      config_path: DEFAULT_CONFIG_PATH,
      config_loader: Config.method(:load!),
      compiler_factory: ->(config) { Compiler.new(config:) },
      listener_factory: nil,
      logger: nil,
      sleeper: Deps::Sleeper.new,
      production_check: nil
    )
      @config_path = config_path
      @config_loader = config_loader
      @compiler_factory = compiler_factory
      @listener_factory = listener_factory
      @logger = logger
      @sleeper = sleeper
      @production_check = production_check || method(:production?)
    end

    def start!
      raise WatcherError, "logica watch is for development only" if @production_check.call

      config = @config_loader.call(@config_path)
      compiler = @compiler_factory.call(config)

      root = config.root.join(PROGRAMS_DIR).to_s
      listener = build_listener(root, compiler)

      info "[logica] watching #{root}..."
      listener.start
      @sleeper.sleep
    end

    private

    def build_listener(root, compiler)
      factory = @listener_factory || default_listener_factory
      factory.call(root, only: /\.l\z/, wait_for_delay: 1.0) do |_modified = nil, _added = nil, _removed = nil|
        info "[logica] change detected, compiling..."
        compiler.compile_all!
        info "[logica] compile done"
      rescue StandardError => e
        warn "[logica] compile failed: #{e.class}: #{e.message}"
      end
    end

    def default_listener_factory
      require "listen"
      Listen.method(:to)
    end

    def production?
      defined?(Rails) && Rails.respond_to?(:env) && Rails.env.production?
    end

    def info(message)
      logger&.info(message) || puts(message)
    end

    def warn(message)
      logger&.warn(message) || Kernel.warn(message)
    end

    def logger
      return @logger if @logger
      return Rails.logger if defined?(Rails) && Rails.respond_to?(:logger) && Rails.logger

      nil
    end
  end
end
