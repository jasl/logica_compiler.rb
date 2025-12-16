# frozen_string_literal: true

require_relative "../watcher"
require_relative "base"
require_relative "logica"

module LogicaCompiler
  module Commands
    class Watch < Base
      def initialize(watcher: Watcher, **kwargs)
        super(**kwargs)
        @watcher = watcher
        @logica = Logica.new(**kwargs)
      end

      def call(config_path:, logica_bin_override: nil)
        config = load_config(config_path:, logica_bin_override:)
        @logica.ensure_available!(config, allow_install: true)
        @watcher.start!(config_path:)
      end
    end
  end
end
