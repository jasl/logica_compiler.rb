# frozen_string_literal: true

require_relative "base"

module LogicaCompiler
  module Commands
    class Version < Base
      def call(config_path:, logica_bin_override: nil)
        config = load_config(config_path:, logica_bin_override:)
        config.pinned_logica_version || "unknown"
      end
    end
  end
end
