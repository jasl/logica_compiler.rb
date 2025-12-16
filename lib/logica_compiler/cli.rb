# frozen_string_literal: true

require "thor"

require_relative "commands/clean"
require_relative "commands/compile"
require_relative "commands/install"
require_relative "commands/version"
require_relative "commands/watch"

module LogicaCompiler
  class CLI < Thor
    default_command :help

    class_option :config,
                 type: :string,
                 default: "logica/config.yml",
                 desc: "Path to logica config.yml"

    class_option :logica_bin,
                 type: :string,
                 desc: "Override LOGICA_BIN (path or command name)"

    desc "install", "Install pinned Logica CLI into tmp/logica_venv (no-op if LOGICA_BIN points elsewhere)"
    def install
      with_cli_errors do
        version = Commands::Install.new.call(config_path: options[:config], logica_bin_override: options[:logica_bin])
        say version, :green
      end
    end

    desc "compile [NAME]", "Compile Logica programs to digested SQL + manifest (optional single query NAME)"
    method_option :force, type: :boolean, default: false, desc: "Recompile even if digest matches"
    method_option :prune, type: :boolean, default: true, desc: "Remove old digested artifacts for the same query name"
    def compile(name = nil)
      with_cli_errors do
        Commands::Compile.new.call(
          config_path: options[:config],
          logica_bin_override: options[:logica_bin],
          name:,
          force: options[:force],
          prune: options[:prune]
        )
      end
    end

    desc "clean", "Remove compiled SQL artifacts (keeps logica/compiled/.keep)"
    def clean
      with_cli_errors do
        Commands::Clean.new.call(config_path: options[:config], logica_bin_override: options[:logica_bin])
      end
    end

    desc "watch", "Watch logica/programs and auto-compile on change (development only)"
    def watch
      with_cli_errors do
        Commands::Watch.new.call(config_path: options[:config], logica_bin_override: options[:logica_bin])
      end
    end

    desc "version", "Print pinned/installed Logica version"
    def version
      with_cli_errors do
        say Commands::Version.new.call(config_path: options[:config], logica_bin_override: options[:logica_bin])
      end
    end

    private

    def with_cli_errors
      yield
    rescue LogicaCompiler::Error => e
      raise Thor::Error, e.message
    end
  end
end
