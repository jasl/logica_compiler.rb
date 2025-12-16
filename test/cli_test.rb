# frozen_string_literal: true

require "test_helper"
require "json"
require "tmpdir"
require "fileutils"
require "pathname"

require "logica_compiler/cli"

class CliTest < Minitest::Test
  def test_commands_apply_logica_bin_override_only_during_config_load
    env = LogicaCompiler::Deps::Env.new

    seen = []
    config_loader = lambda do |_path|
      seen << ENV.fetch("LOGICA_BIN", nil)
      Struct.new(:pinned_logica_version).new("9.9.9")
    end

    cmd = LogicaCompiler::Commands::Version.new(env:, config_loader:)
    env.with_temp("LOGICA_BIN" => "previous") do
      assert_equal "9.9.9", cmd.call(config_path: "ignored", logica_bin_override: "/tmp/fake_logica")
      assert_equal "previous", ENV.fetch("LOGICA_BIN")
    end

    assert_equal ["/tmp/fake_logica"], seen
  end

  def test_logica_ensure_available_raises_for_missing_path
    config = Struct.new(:logica_bin, :root).new("/tmp/missing_logica", Pathname("/tmp"))
    logica = LogicaCompiler::Commands::Logica.new(which: ->(_cmd) { nil })

    assert_raises(LogicaCompiler::LogicaError) { logica.ensure_available!(config, allow_install: false) }
  end

  def test_logica_ensure_available_accepts_command_on_path
    config = Struct.new(:logica_bin, :root).new("logica", Pathname("/tmp"))
    logica = LogicaCompiler::Commands::Logica.new(which: ->(_cmd) { "/tmp/logica" })

    assert_nil logica.ensure_available!(config, allow_install: false)
  end

  def test_logica_ensure_available_can_install_default_venv_binary_when_allowed
    Dir.mktmpdir do |dir|
      root = Pathname(dir)
      config = Struct.new(:logica_bin, :root).new(root.join("tmp/logica_venv/bin/logica").to_s, root)

      logica = LogicaCompiler::Commands::Logica.new(which: ->(_cmd) { "/tmp/python" })

      logica.stub(:install_venv_logica!, lambda { |cfg|
        path = Pathname(cfg.logica_bin)
        FileUtils.mkdir_p(path.dirname)
        path.write("#!/usr/bin/env ruby\nexit 0\n")
        FileUtils.chmod(0o755, path)
      }) do
        assert_nil logica.ensure_available!(config, allow_install: true)
      end
    end
  end

  def test_compile_command_raises_for_unknown_query
    Dir.mktmpdir do |dir|
      root = Pathname(dir)
      FileUtils.mkdir_p(root.join("logica/programs"))
      FileUtils.mkdir_p(root.join("logica/compiled"))

      root.join("logica/programs/hello_world.l").write("HelloWorld(x: 1);\n")
      root.join("logica/config.yml").write(<<~YAML)
        engine: postgres
        output_dir: logica/compiled
        logica_bin: logica
        queries:
          hello_world:
            program: logica/programs/hello_world.l
            predicate: HelloWorld
      YAML

      config_loader = ->(path) { LogicaCompiler::Config.load!(path, root:) }
      command =
        LogicaCompiler::Commands::Compile.new(
          config_loader:,
          which: ->(_cmd) { "/tmp/logica" },
          compiler_factory: ->(_config) { Object.new }
        )

      error =
        assert_raises(LogicaCompiler::UnknownQueryError) do
          command.call(config_path: "logica/config.yml", name: "missing", force: false, prune: true)
        end
      assert_match(/Unknown Logica query: missing/, error.message)
      assert_match(/Known:/, error.message)
    end
  end

  def test_compile_command_recovers_from_invalid_manifest
    Dir.mktmpdir do |dir|
      root = Pathname(dir)
      FileUtils.mkdir_p(root.join("logica/programs"))
      FileUtils.mkdir_p(root.join("logica/compiled"))

      root.join("logica/programs/user_report.l").write("UserReport(user_id: 1, value: \"a\");\n")
      root.join("logica/config.yml").write(<<~YAML)
        engine: postgres
        output_dir: logica/compiled
        logica_bin: logica
        queries:
          user_report:
            program: logica/programs/user_report.l
            predicate: UserReport
      YAML

      config = LogicaCompiler::Config.load!("logica/config.yml", root:)
      File.write(config.manifest_path, "{not-json")

      compiler = Object.new
      def compiler.logica_version = "1.2.3"

      def compiler.compile_one!(name:, query:, force:, prune:)
        _ = name
        _ = query
        _ = force
        _ = prune
        { "digest" => "sha256:abc", "sql" => "user_report-abc.sql", "meta" => "user_report-abc.meta.json" }
      end

      fixed_clock = Object.new
      def fixed_clock.now_utc = Time.at(0).utc

      config_loader = ->(path) { LogicaCompiler::Config.load!(path, root:) }
      command =
        LogicaCompiler::Commands::Compile.new(
          config_loader:,
          which: ->(_cmd) { "/tmp/logica" },
          compiler_factory: ->(_config) { compiler },
          clock: fixed_clock
        )

      command.call(config_path: "logica/config.yml", name: "user_report", force: false, prune: true)

      data = JSON.parse(File.read(config.manifest_path))
      assert_equal "postgres", data.fetch("engine")
      assert_equal "1.2.3", data.dig("logica", "version")
      assert_equal "1970-01-01T00:00:00Z", data.fetch("compiled_at")
      assert_equal "sha256:abc", data.dig("queries", "user_report", "digest")
    end
  end

  def test_compile_command_preserves_other_query_entries
    Dir.mktmpdir do |dir|
      root = Pathname(dir)
      FileUtils.mkdir_p(root.join("logica/programs"))
      FileUtils.mkdir_p(root.join("logica/compiled"))

      root.join("logica/programs/user_report.l").write("UserReport(user_id: 1, value: \"a\");\n")
      root.join("logica/config.yml").write(<<~YAML)
        engine: postgres
        output_dir: logica/compiled
        logica_bin: logica
        queries:
          user_report:
            program: logica/programs/user_report.l
            predicate: UserReport
      YAML

      config = LogicaCompiler::Config.load!("logica/config.yml", root:)
      existing =
        LogicaCompiler::Manifest.build(
          engine: "postgres",
          logica_version: "0.0.1",
          queries: { other: { "digest" => "sha256:old", "sql" => "other-old.sql", "meta" => "other-old.meta.json" } }
        )
      LogicaCompiler::Manifest.write!(config.manifest_path, existing)

      compiler = Object.new
      def compiler.logica_version = "1.2.3"

      def compiler.compile_one!(name:, query:, force:, prune:)
        _ = name
        _ = query
        _ = force
        _ = prune
        { "digest" => "sha256:new", "sql" => "user_report-new.sql", "meta" => "user_report-new.meta.json" }
      end

      config_loader = ->(path) { LogicaCompiler::Config.load!(path, root:) }
      command =
        LogicaCompiler::Commands::Compile.new(
          config_loader:,
          which: ->(_cmd) { "/tmp/logica" },
          compiler_factory: ->(_config) { compiler }
        )

      command.call(config_path: "logica/config.yml", name: "user_report", force: false, prune: true)

      data = JSON.parse(File.read(config.manifest_path))
      assert_equal "sha256:old", data.dig("queries", "other", "digest")
      assert_equal "sha256:new", data.dig("queries", "user_report", "digest")
    end
  end

  def test_install_command_returns_pinned_version
    Dir.mktmpdir do |dir|
      root = Pathname(dir)
      FileUtils.mkdir_p(root.join("logica"))

      root.join("logica/requirements.txt").write("logica==9.9.9\n")
      root.join("logica/config.yml").write(<<~YAML)
        engine: postgres
        output_dir: logica/compiled
        logica_bin: logica
        queries: {}
      YAML

      config_loader = ->(path) { LogicaCompiler::Config.load!(path, root:) }
      command =
        LogicaCompiler::Commands::Install.new(
          config_loader:,
          which: ->(_cmd) { "/tmp/logica" }
        )

      assert_equal "9.9.9", command.call(config_path: "logica/config.yml")
    end
  end

  def test_clean_command_removes_artifacts_except_keep
    Dir.mktmpdir do |dir|
      root = Pathname(dir)
      compiled = root.join("logica/compiled")
      FileUtils.mkdir_p(compiled)
      compiled.join(".keep").write("")
      compiled.join("a.sql").write("SELECT 1\n")
      FileUtils.mkdir_p(compiled.join("nested"))
      compiled.join("nested/file.txt").write("x\n")

      root.join("logica/config.yml").write(<<~YAML)
        engine: postgres
        output_dir: logica/compiled
        queries: {}
      YAML

      config_loader = ->(path) { LogicaCompiler::Config.load!(path, root:) }
      LogicaCompiler::Commands::Clean.new(config_loader:).call(config_path: "logica/config.yml")

      assert_predicate compiled.join(".keep"), :exist?
      refute_predicate compiled.join("a.sql"), :exist?
      refute_predicate compiled.join("nested"), :exist?
    end
  end

  def test_watch_command_delegates_to_watcher
    Dir.mktmpdir do |dir|
      root = Pathname(dir)
      FileUtils.mkdir_p(root.join("logica"))

      root.join("logica/config.yml").write(<<~YAML)
        engine: postgres
        output_dir: logica/compiled
        logica_bin: logica
        queries: {}
      YAML

      calls = []
      watcher = Object.new
      watcher.define_singleton_method(:start!) { |config_path:| calls << config_path }

      config_loader = ->(path) { LogicaCompiler::Config.load!(path, root:) }
      command =
        LogicaCompiler::Commands::Watch.new(
          watcher:,
          config_loader:,
          which: ->(_cmd) { "/tmp/logica" }
        )

      command.call(config_path: "logica/config.yml")
      assert_equal ["logica/config.yml"], calls
    end
  end

  def test_logica_install_venv_raises_when_python_missing
    Dir.mktmpdir do |dir|
      root = Pathname(dir)
      FileUtils.mkdir_p(root.join("logica"))

      root.join("logica/requirements.txt").write("logica==9.9.9\n")

      config = Struct.new(:root, :requirements_path).new(root, root.join("logica/requirements.txt"))
      logica = LogicaCompiler::Commands::Logica.new(which: ->(_cmd) { nil })

      error = assert_raises(LogicaCompiler::LogicaError) { logica.install_venv_logica!(config) }
      assert_match(/python3 not found/i, error.message)
    end
  end

  def test_logica_install_venv_raises_when_requirements_missing
    Dir.mktmpdir do |dir|
      root = Pathname(dir)

      config = Struct.new(:root, :requirements_path).new(root, root.join("logica/requirements.txt"))
      logica = LogicaCompiler::Commands::Logica.new(which: ->(_cmd) { "/tmp/python3" })

      error = assert_raises(LogicaCompiler::LogicaError) { logica.install_venv_logica!(config) }
      assert_match(/requirements not found/i, error.message)
    end
  end

  def test_logica_install_venv_noops_when_stamp_matches
    Dir.mktmpdir do |dir|
      root = Pathname(dir)
      FileUtils.mkdir_p(root.join("logica"))

      requirements = root.join("logica/requirements.txt")
      requirements.write("logica==9.9.9\n")

      venv_dir = root.join("tmp/logica_venv")
      FileUtils.mkdir_p(venv_dir)
      sha = Digest::SHA256.hexdigest(requirements.read)
      venv_dir.join(".requirements.sha256").write("#{sha}\n")

      shell = Object.new
      shell.define_singleton_method(:system) { |*| raise "unexpected system call" }

      config = Struct.new(:root, :requirements_path).new(root, requirements)
      logica = LogicaCompiler::Commands::Logica.new(which: ->(_cmd) { "/tmp/python3" }, shell:)

      assert_nil logica.install_venv_logica!(config)
    end
  end

  def test_cli_dispatches_to_commands
    cli = LogicaCompiler::CLI.new

    said = []
    cli.stub(:say, ->(msg, color = nil) { said << [msg, color] }) do
      cli.stub(:options, { config: "logica/config.yml", logica_bin: "/tmp/logica" }) do
        fake_install = Object.new
        fake_install.define_singleton_method(:call) { |**_kwargs| "1.2.3" }
        LogicaCompiler::Commands::Install.stub(:new, ->(*, **) { fake_install }) do
          cli.install
        end

        fake_version = Object.new
        fake_version.define_singleton_method(:call) { |**_kwargs| "9.9.9" }
        LogicaCompiler::Commands::Version.stub(:new, ->(*, **) { fake_version }) do
          cli.version
        end
      end
    end

    assert_equal [["1.2.3", :green], ["9.9.9", nil]], said

    calls = []
    cli.stub(:options, { config: "cfg", logica_bin: nil, force: true, prune: false }) do
      fake_compile = Object.new
      fake_compile.define_singleton_method(:call) { |**kwargs| calls << kwargs }
      LogicaCompiler::Commands::Compile.stub(:new, ->(*, **) { fake_compile }) do
        cli.compile("hello_world")
      end
    end
    assert_equal 1, calls.length
    assert_equal "cfg", calls.first.fetch(:config_path)
    assert_nil calls.first.fetch(:logica_bin_override)
    assert_equal "hello_world", calls.first.fetch(:name)
    assert_equal true, calls.first.fetch(:force)
    assert_equal false, calls.first.fetch(:prune)

    calls = []
    cli.stub(:options, { config: "cfg", logica_bin: "bin" }) do
      fake_clean = Object.new
      fake_clean.define_singleton_method(:call) { |**kwargs| calls << kwargs }
      LogicaCompiler::Commands::Clean.stub(:new, ->(*, **) { fake_clean }) do
        cli.clean
      end
    end
    assert_equal [{ config_path: "cfg", logica_bin_override: "bin" }], calls

    calls = []
    cli.stub(:options, { config: "cfg", logica_bin: "bin" }) do
      fake_watch = Object.new
      fake_watch.define_singleton_method(:call) { |**kwargs| calls << kwargs }
      LogicaCompiler::Commands::Watch.stub(:new, ->(*, **) { fake_watch }) do
        cli.watch
      end
    end
    assert_equal [{ config_path: "cfg", logica_bin_override: "bin" }], calls
  end
end
