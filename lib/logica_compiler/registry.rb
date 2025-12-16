# frozen_string_literal: true

require "json"

module LogicaCompiler
  class Registry
    class MissingManifestError < StandardError; end
    class InvalidManifestError < StandardError; end
    class MissingQueryError < KeyError; end

    def self.unavailable(message:)
      Unavailable.new(message: message.to_s)
    end

    def self.load(manifest_path:, output_dir:, strict: false)
      new(manifest_path:, output_dir:).tap { _1.load!(strict:) }
    rescue Errno::ENOENT, MissingManifestError, InvalidManifestError => e
      raise if strict

      return unavailable(message: "#{e.message}. Run `bin/logica compile` again.") if e.is_a?(InvalidManifestError)

      MissingManifest.new(manifest_path:)
    end

    def initialize(manifest_path:, output_dir:)
      @manifest_path = manifest_path.to_s
      @output_dir = output_dir.to_s
      @entries = nil
      @sql_cache = {}
    end

    def load!(strict: false)
      data = JSON.parse(File.read(@manifest_path))
      queries = data.is_a?(Hash) ? data["queries"] : nil

      unless queries.is_a?(Hash)
        raise InvalidManifestError, "Invalid Logica manifest #{@manifest_path}: missing or invalid 'queries' key"
      end

      @entries = queries
      self
    rescue Errno::ENOENT
      raise MissingManifestError, "Missing Logica manifest: #{@manifest_path}" if strict

      raise
    rescue JSON::ParserError => e
      raise InvalidManifestError, "Invalid Logica manifest #{@manifest_path}: #{e.message}"
    end

    def sql(name)
      name = name.to_s
      entry = entries.fetch(name) { raise MissingQueryError, "Unknown Logica query: #{name}" }
      sql_file = entry.fetch("sql")
      @sql_cache[name] ||= File.read(File.join(@output_dir, sql_file))
    end

    def entry(name)
      entries.fetch(name.to_s) { raise MissingQueryError, "Unknown Logica query: #{name}" }
    end

    private

    def entries
      @entries || raise(MissingManifestError, "Registry not loaded")
    end

    class MissingManifest
      def initialize(manifest_path:)
        @manifest_path = manifest_path.to_s
      end

      def sql(_name)
        raise MissingManifestError,
              "Missing Logica manifest: #{@manifest_path}. Run `bin/logica compile` first."
      end

      def entry(_name)
        raise MissingManifestError,
              "Missing Logica manifest: #{@manifest_path}. Run `bin/logica compile` first."
      end
    end

    class Unavailable
      def initialize(message:)
        @message = message.to_s
      end

      def sql(_name)
        raise MissingManifestError, @message
      end

      def entry(_name)
        raise MissingManifestError, @message
      end
    end
  end
end
