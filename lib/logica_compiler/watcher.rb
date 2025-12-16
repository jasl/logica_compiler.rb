# frozen_string_literal: true

module LogicaCompiler
  class Watcher
    def self.start!(config_path: "logica/config.yml")
      if defined?(Rails) && Rails.respond_to?(:env) && Rails.env.production?
        raise "logica watch is for development only"
      end

      require "listen"

      config = Config.load!(config_path)
      compiler = Compiler.new(config:)

      root = config.root.join("logica/programs").to_s
      listener = Listen.to(root, only: /\.l\z/, wait_for_delay: 1.0) do
        log "[logica] change detected, compiling..."
        compiler.compile_all!
        log "[logica] compile done"
      rescue StandardError => e
        warn "[logica] compile failed: #{e.class}: #{e.message}"
      end

      log "[logica] watching #{root}..."
      listener.start
      sleep
    end

    def self.log(message)
      if defined?(Rails) && Rails.respond_to?(:logger) && (logger = Rails.logger)
        logger.info(message)
      else
        puts(message)
      end
    end
  end
end
