# frozen_string_literal: true

require_relative "../config"
require_relative "../deps/clock"
require_relative "../deps/env"
require_relative "../deps/shell"
require_relative "../util"

module LogicaCompiler
  module Commands
    class Base
      def initialize(
        env: Deps::Env.new,
        shell: Deps::Shell.new,
        clock: Deps::Clock.new,
        config_loader: Config.method(:load!),
        which: Util.method(:which)
      )
        @env = env
        @shell = shell
        @clock = clock
        @config_loader = config_loader
        @which = which
      end

      private

      attr_reader :env, :shell, :clock, :config_loader, :which

      def with_logica_bin_override(override)
        value = override.to_s
        value = nil if value.strip.empty?
        return yield if value.nil?

        env.with_temp("LOGICA_BIN" => value) { yield }
      end

      def load_config(config_path:, logica_bin_override: nil)
        with_logica_bin_override(logica_bin_override) do
          config_loader.call(config_path)
        end
      end
    end
  end
end
