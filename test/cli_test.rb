# frozen_string_literal: true

require "test_helper"
require "tmpdir"
require "fileutils"
require "pathname"

require "logica_compiler/cli"

class CliTest < Minitest::Test
  def test_with_logica_bin_override_sets_env_and_restores
    cli = LogicaCompiler::CLI.new

    with_env("LOGICA_BIN" => "previous") do
      cli.stub(:options, { logica_bin: "/tmp/fake_logica" }) do
        cli.send(:with_logica_bin_override) do
          assert_equal "/tmp/fake_logica", ENV.fetch("LOGICA_BIN")
        end
      end

      assert_equal "previous", ENV.fetch("LOGICA_BIN")
    end
  end

  def test_ensure_logica_available_raises_for_missing_path
    Dir.mktmpdir do |dir|
      root = Pathname(dir)
      FileUtils.mkdir_p(root.join("logica"))

      missing = root.join("tmp/missing_logica").to_s
      root.join("logica/config.yml").write(<<~YAML)
        engine: postgres
        output_dir: logica/compiled
        logica_bin: #{missing}
        queries: {}
      YAML

      config = LogicaCompiler::Config.load!("logica/config.yml", root:)
      cli = LogicaCompiler::CLI.new

      assert_raises(Thor::Error) { cli.send(:ensure_logica_available!, config, allow_install: false) }
    end
  end

  def test_ensure_logica_available_accepts_command_on_path
    Dir.mktmpdir do |dir|
      root = Pathname(dir)
      FileUtils.mkdir_p(root.join("logica"))

      root.join("logica/config.yml").write(<<~YAML)
        engine: postgres
        output_dir: logica/compiled
        logica_bin: logica
        queries: {}
      YAML

      config = LogicaCompiler::Config.load!("logica/config.yml", root:)
      cli = LogicaCompiler::CLI.new

      Dir.mktmpdir do |bindir|
        logica = Pathname(bindir).join("logica")
        logica.write("#!/usr/bin/env ruby\nexit 0\n")
        FileUtils.chmod(0o755, logica)

        with_env("PATH" => "#{bindir}#{File::PATH_SEPARATOR}") do
          assert_nil cli.send(:ensure_logica_available!, config, allow_install: false)
        end
      end
    end
  end

  def test_ensure_logica_available_can_install_default_venv_binary_when_allowed
    Dir.mktmpdir do |dir|
      root = Pathname(dir)
      FileUtils.mkdir_p(root.join("logica"))

      root.join("logica/config.yml").write(<<~YAML)
        engine: postgres
        output_dir: logica/compiled
        queries: {}
      YAML

      with_env("PATH" => "", "LOGICA_BIN" => nil) do
        config = LogicaCompiler::Config.load!("logica/config.yml", root:)
        cli = LogicaCompiler::CLI.new

        cli.stub(:install_venv_logica!, lambda { |cfg|
          path = Pathname(cfg.logica_bin)
          FileUtils.mkdir_p(path.dirname)
          path.write("#!/usr/bin/env ruby\nexit 0\n")
          FileUtils.chmod(0o755, path)
        }) do
          assert_nil cli.send(:ensure_logica_available!, config, allow_install: true)
        end
      end
    end
  end

  def test_compile_one_and_update_manifest_raises_for_unknown_query
    Dir.mktmpdir do |dir|
      root = Pathname(dir)
      FileUtils.mkdir_p(root.join("logica/programs"))
      FileUtils.mkdir_p(root.join("logica/compiled"))

      root.join("logica/programs/hello_world.l").write("HelloWorld(x: 1);\n")
      root.join("logica/config.yml").write(<<~YAML)
        engine: postgres
        output_dir: logica/compiled
        queries:
          hello_world:
            program: logica/programs/hello_world.l
            predicate: HelloWorld
      YAML

      config = LogicaCompiler::Config.load!("logica/config.yml", root:)
      cli = LogicaCompiler::CLI.new

      error =
        assert_raises(Thor::Error) do
          cli.send(:compile_one_and_update_manifest!, Object.new, config, "missing", force: false, prune: true)
        end
      assert_match(/Unknown Logica query: missing/, error.message)
      assert_match(/Known:/, error.message)
    end
  end

  def test_compile_one_and_update_manifest_recovers_from_invalid_manifest
    Dir.mktmpdir do |dir|
      root = Pathname(dir)
      FileUtils.mkdir_p(root.join("logica/programs"))
      FileUtils.mkdir_p(root.join("logica/compiled"))

      root.join("logica/programs/user_report.l").write("UserReport(user_id: 1, value: \"a\");\n")
      root.join("logica/config.yml").write(<<~YAML)
        engine: postgres
        output_dir: logica/compiled
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

      cli = LogicaCompiler::CLI.new
      cli.send(:compile_one_and_update_manifest!, compiler, config, "user_report", force: false, prune: true)

      data = JSON.parse(File.read(config.manifest_path))
      assert_equal "postgres", data.fetch("engine")
      assert_equal "1.2.3", data.dig("logica", "version")
      assert data.fetch("compiled_at")
      assert_equal "sha256:abc", data.dig("queries", "user_report", "digest")
    end
  end

  def test_compile_one_and_update_manifest_preserves_other_query_entries
    Dir.mktmpdir do |dir|
      root = Pathname(dir)
      FileUtils.mkdir_p(root.join("logica/programs"))
      FileUtils.mkdir_p(root.join("logica/compiled"))

      root.join("logica/programs/user_report.l").write("UserReport(user_id: 1, value: \"a\");\n")
      root.join("logica/config.yml").write(<<~YAML)
        engine: postgres
        output_dir: logica/compiled
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

      cli = LogicaCompiler::CLI.new
      cli.send(:compile_one_and_update_manifest!, compiler, config, "user_report", force: false, prune: true)

      data = JSON.parse(File.read(config.manifest_path))
      assert_equal "sha256:old", data.dig("queries", "other", "digest")
      assert_equal "sha256:new", data.dig("queries", "user_report", "digest")
    end
  end

  private

  def with_env(updates)
    previous = {}
    updates.each do |k, v|
      previous[k] = ENV.key?(k) ? ENV[k] : :__missing__
      v.nil? ? ENV.delete(k) : ENV[k] = v
    end
    yield
  ensure
    previous.each do |k, v|
      v == :__missing__ ? ENV.delete(k) : ENV[k] = v
    end
  end
end
