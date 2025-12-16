# frozen_string_literal: true

require_relative "../compiler"
require_relative "../manifest"
require_relative "base"
require_relative "logica"

module LogicaCompiler
  module Commands
    class Compile < Base
      def initialize(compiler_factory: ->(config) { Compiler.new(config:) }, **kwargs)
        super(**kwargs)
        @logica = Logica.new(**kwargs)
        @compiler_factory = compiler_factory
      end

      def call(config_path:, logica_bin_override: nil, name: nil, force: false, prune: true)
        config = load_config(config_path:, logica_bin_override:)
        @logica.ensure_available!(config, allow_install: true)

        compiler = @compiler_factory.call(config)

        if name.to_s.strip.empty?
          compiler.compile_all!(force:, prune:)
        else
          compile_one_and_update_manifest!(compiler, config, name.to_s, force:, prune:)
        end
      end

      private

      def compile_one_and_update_manifest!(compiler, config, name, force:, prune:)
        sym = name.to_sym
        unless config.queries.key?(sym)
          raise UnknownQueryError, "Unknown Logica query: #{name}. Known: #{config.queries.keys.map(&:to_s).sort.join(", ")}"
        end

        entry = compiler.compile_one!(name:, query: config.queries.fetch(sym), force:, prune:)

        manifest =
          begin
            Manifest.load(config.manifest_path)
          rescue StandardError
            Manifest.build(engine: config.engine, logica_version: compiler.logica_version, queries: {})
          end

        manifest["engine"] = config.engine
        manifest["logica"] = { "pypi" => "logica", "version" => compiler.logica_version.to_s }
        manifest["compiled_at"] = clock.now_utc.iso8601
        manifest["queries"] ||= {}
        manifest["queries"][name.to_s] = entry
        Manifest.write!(config.manifest_path, manifest)
        manifest
      end
    end
  end
end
