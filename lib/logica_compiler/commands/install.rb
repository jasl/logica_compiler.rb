# frozen_string_literal: true

require_relative "base"
require_relative "logica"

module LogicaCompiler
  module Commands
    class Install < Base
      def initialize(**kwargs)
        super
        @logica = Logica.new(**kwargs)
      end

      def call(config_path:, logica_bin_override: nil)
        config = load_config(config_path:, logica_bin_override:)
        @logica.ensure_available!(config, allow_install: true)
        config.pinned_logica_version || "unknown"
      end
    end
  end
end
