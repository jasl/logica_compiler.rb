# frozen_string_literal: true

require "fileutils"
require "json"
require "time"

module LogicaCompiler
  class Manifest
    VERSION = 1

    def self.build(engine:, logica_version:, queries:, compiled_at: Time.now.utc)
      {
        "version" => VERSION,
        "engine" => engine.to_s,
        "logica" => { "pypi" => "logica", "version" => logica_version.to_s },
        "compiled_at" => compiled_at.iso8601,
        "queries" => queries.transform_keys(&:to_s),
      }
    end

    def self.load(path)
      JSON.parse(File.read(path.to_s))
    end

    def self.write!(path, manifest)
      path = path.to_s
      FileUtils.mkdir_p(File.dirname(path))
      File.write(path, "#{JSON.pretty_generate(manifest)}\n")
    end
  end
end
