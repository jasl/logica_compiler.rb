# frozen_string_literal: true

require_relative "watcher"
require_relative "util"

require "thor"
require "pathname"
require "fileutils"
require "digest"
require "time"

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
      with_logica_bin_override do
        config = Config.load!(options[:config])
        ensure_logica_available!(config, allow_install: true)
        say logica_package_version(config), :green
      end
    end

    desc "compile [NAME]", "Compile Logica programs to digested SQL + manifest (optional single query NAME)"
    method_option :force, type: :boolean, default: false, desc: "Recompile even if digest matches"
    method_option :prune, type: :boolean, default: true, desc: "Remove old digested artifacts for the same query name"
    def compile(name = nil)
      with_logica_bin_override do
        config = Config.load!(options[:config])
        ensure_logica_available!(config, allow_install: true)

        compiler = Compiler.new(config:)
        if name.to_s.strip.empty?
          compiler.compile_all!(force: options[:force], prune: options[:prune])
        else
          compile_one_and_update_manifest!(compiler, config, name.to_s, force: options[:force], prune: options[:prune])
        end
      end
    end

    desc "clean", "Remove compiled SQL artifacts (keeps logica/compiled/.keep)"
    def clean
      config = Config.load!(options[:config])
      dir = config.output_dir_path
      FileUtils.mkdir_p(dir)

      Dir.glob(dir.join("*").to_s).each do |path|
        next if File.basename(path) == ".keep"

        FileUtils.rm_rf(path)
      end
    end

    desc "watch", "Watch logica/programs and auto-compile on change (development only)"
    def watch
      with_logica_bin_override do
        config = Config.load!(options[:config])
        ensure_logica_available!(config, allow_install: true)
        Watcher.start!(config_path: options[:config])
      end
    end

    desc "version", "Print pinned/installed Logica version"
    def version
      with_logica_bin_override do
        config = Config.load!(options[:config])
        say logica_package_version(config)
      end
    end

    private

    def with_logica_bin_override
      previous = ENV["LOGICA_BIN"]
      ENV["LOGICA_BIN"] = options[:logica_bin] if options[:logica_bin].to_s.strip != ""
      yield
    ensure
      ENV["LOGICA_BIN"] = previous
    end

    def compile_one_and_update_manifest!(compiler, config, name, force:, prune:)
      sym = name.to_sym
      unless config.queries.key?(sym)
        raise Thor::Error, "Unknown Logica query: #{name}. Known: #{config.queries.keys.map(&:to_s).sort.join(", ")}"
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
      manifest["compiled_at"] = Time.now.utc.iso8601
      manifest["queries"] ||= {}
      manifest["queries"][name.to_s] = entry
      Manifest.write!(config.manifest_path, manifest)
    end

    def ensure_logica_available!(config, allow_install:)
      bin = config.logica_bin.to_s

      if bin.include?(File::SEPARATOR) || bin.start_with?(".")
        return if File.executable?(bin)

        if allow_install && bin == default_venv_logica_path(config).to_s
          install_venv_logica!(config)
          return if File.executable?(bin)
        end

        raise Thor::Error, "Logica CLI not found: #{bin.inspect}"
      end

      return if Util.which(bin)

      raise Thor::Error, "Logica CLI #{bin.inspect} not found on PATH. Run `bin/logica install` or set LOGICA_BIN."
    end

    def install_venv_logica!(config)
      python = ENV.fetch("LOGICA_PYTHON", "python3")
      requirements = Pathname(ENV.fetch("LOGICA_REQUIREMENTS", config.requirements_path.to_s))
      venv_dir = Pathname(ENV.fetch("LOGICA_VENV", config.root.join("tmp/logica_venv").to_s))

      raise Thor::Error, "python3 not found. Install Python 3 and try again." unless Util.which(python)

      raise Thor::Error, "requirements not found: #{requirements}" unless requirements.exist?

      FileUtils.mkdir_p(venv_dir.parent)
      system!(python, "-m", "venv", venv_dir.to_s) unless venv_dir.exist?

      stamp = venv_dir.join(".requirements.sha256")
      req_sha = Digest::SHA256.hexdigest(requirements.read)

      return if stamp.exist? && stamp.read.strip == req_sha

      venv_python = venv_dir.join(Util.venv_bin_dir, "python").to_s
      system!(venv_python, "-m", "pip", "install", "--upgrade", "pip")
      system!(venv_python, "-m", "pip", "install", "-r", requirements.to_s)

      stamp.write(req_sha)
    end

    def logica_package_version(config)
      pinned = config.pinned_logica_version
      bin = config.logica_bin.to_s

      # If using our default venv path, try to read installed version from the venv.
      if bin.include?(File::SEPARATOR) && bin == default_venv_logica_path(config).to_s
        venv_dir = Pathname(ENV.fetch("LOGICA_VENV", config.root.join("tmp/logica_venv").to_s))
        venv_python = venv_dir.join(Util.venv_bin_dir, "python").to_s
        if File.executable?(venv_python)
          out = capture!(venv_python, "-c", "import importlib.metadata as m; print(m.version('logica'))")
          return out.strip unless out.to_s.strip.empty?
        end
      end

      pinned || "unknown"
    end

    def default_venv_logica_path(config)
      config.root.join("tmp/logica_venv", Util.venv_bin_dir, "logica")
    end

    def system!(*args)
      ok = system(*args)
      raise Thor::Error, "Command failed: #{args.join(" ")}" unless ok
    end

    def capture!(*args)
      require "open3"
      out, err, status = Open3.capture3(*args)
      raise Thor::Error, err.to_s unless status.success?

      out
    end
  end
end
