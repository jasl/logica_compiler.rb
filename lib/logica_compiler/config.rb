# frozen_string_literal: true

require "pathname"
require "yaml"

require_relative "util"

module LogicaCompiler
  class Config
    Query = Struct.new(:program, :predicate, keyword_init: true) do
      def initialize(program:, predicate:)
        super(program: program.to_s, predicate: predicate.to_s)
      end
    end

    DEFAULT_ENGINE = "postgres"
    DEFAULT_OUTPUT_DIR = "logica/compiled"

    attr_reader :config_path, :root, :engine, :output_dir, :queries, :logica_bin

    def self.load!(config_path = "logica/config.yml", root: default_root)
      new(config_path:, root:).tap(&:load!)
    end

    def self.default_root
      if defined?(Rails) && Rails.respond_to?(:root)
        Rails.root
      else
        Pathname.new(Dir.pwd)
      end
    end

    def initialize(config_path:, root:)
      @config_path = config_path.to_s
      @root = Pathname(root)
      @engine = DEFAULT_ENGINE
      @output_dir = DEFAULT_OUTPUT_DIR
      @queries = {}
      @logica_bin = env_logica_bin
    end

    def load!
      data = YAML.safe_load(File.read(absolute_path(config_path)), permitted_classes: [], aliases: false) || {}

      @engine = (data["engine"] || DEFAULT_ENGINE).to_s
      @output_dir = (data["output_dir"] || DEFAULT_OUTPUT_DIR).to_s
      @logica_bin ||= (data["logica_bin"] || default_logica_bin).to_s

      queries = (data["queries"] || {}).to_h
      @queries = queries.each_with_object({}) do |(name, attrs), h|
        attrs = attrs.to_h
        h[name.to_sym] = Query.new(
          program: attrs.fetch("program"),
          predicate: attrs.fetch("predicate")
        )
      end

      self
    end

    def output_dir_path = root.join(output_dir)
    def manifest_path = output_dir_path.join("manifest.json")
    def requirements_path = root.join("logica/requirements.txt")
    def absolute_path(rel_path) = root.join(rel_path).to_s

    def pinned_logica_version
      req = requirements_path
      return nil unless req.exist?

      line = req.read.lines.map(&:strip).find { _1.start_with?("logica==") }
      return nil unless line

      line.split("==", 2).last&.strip
    end

    private

    def env_logica_bin
      value = ENV["LOGICA_BIN"]
      value = nil if value.to_s.strip.empty?
      value
    end

    def default_logica_bin
      # Default lookup order (when LOGICA_BIN / config.yml logica_bin is not set):
      # 1) Project python venv: .venv/bin/logica (or .venv/Scripts/logica.exe on Windows)
      # 2) System-installed logica on PATH
      # 3) Gem-managed venv: tmp/logica_venv/.../logica (installed via `bin/logica install`)
      project_venv_dir = root.join(".venv", Util.venv_bin_dir)
      if (path = Util.find_executable_in_dir(project_venv_dir, "logica"))
        return path
      end

      return "logica" if Util.which("logica")

      root.join("tmp/logica_venv", Util.venv_bin_dir, "logica")
    end
  end
end
