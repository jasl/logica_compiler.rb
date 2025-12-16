# frozen_string_literal: true

require "test_helper"

require "tmpdir"
require "fileutils"
require "pathname"

class ConfigTest < Minitest::Test
  def test_default_logica_bin_prefers_project_venv_over_path
    Dir.mktmpdir do |dir|
      root = Pathname(dir)
      write_min_config!(root)

      venv_bin = root.join(".venv", venv_bin_dir)
      FileUtils.mkdir_p(venv_bin)

      venv_logica = venv_bin.join("logica")
      venv_logica.write("#!/usr/bin/env bash\nexit 0\n")
      FileUtils.chmod(0o755, venv_logica)

      bin_dir = root.join("tmp/fakebin")
      FileUtils.mkdir_p(bin_dir)

      logica = bin_dir.join("logica")
      logica.write("#!/usr/bin/env bash\nexit 0\n")
      FileUtils.chmod(0o755, logica)

      with_env("LOGICA_BIN" => nil, "PATH" => "#{bin_dir}#{File::PATH_SEPARATOR}#{ENV.fetch("PATH", "")}") do
        config = LogicaCompiler::Config.load!("logica/config.yml", root:)
        assert_equal venv_logica.to_s, config.logica_bin
      end
    end
  end

  def test_default_logica_bin_uses_path_when_project_venv_missing
    Dir.mktmpdir do |dir|
      root = Pathname(dir)
      write_min_config!(root)

      bin_dir = root.join("tmp/fakebin")
      FileUtils.mkdir_p(bin_dir)

      logica = bin_dir.join("logica")
      logica.write("#!/usr/bin/env bash\nexit 0\n")
      FileUtils.chmod(0o755, logica)

      with_env("LOGICA_BIN" => nil, "PATH" => "#{bin_dir}#{File::PATH_SEPARATOR}#{ENV.fetch("PATH", "")}") do
        config = LogicaCompiler::Config.load!("logica/config.yml", root:)
        assert_equal "logica", config.logica_bin
      end
    end
  end

  def test_default_logica_bin_falls_back_to_tmp_venv_path_when_neither_present
    Dir.mktmpdir do |dir|
      root = Pathname(dir)
      write_min_config!(root)

      with_env("LOGICA_BIN" => nil, "PATH" => "") do
        config = LogicaCompiler::Config.load!("logica/config.yml", root:)
        assert_equal root.join("tmp/logica_venv", venv_bin_dir, "logica").to_s, config.logica_bin
      end
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

  def write_min_config!(root)
    FileUtils.mkdir_p(root.join("logica"))
    root.join("logica/config.yml").write(<<~YAML)
      engine: postgres
      output_dir: logica/compiled
      queries:
        hello_world:
          program: logica/programs/hello_world.l
          predicate: Greet
    YAML
  end

  def venv_bin_dir
    Gem.win_platform? ? "Scripts" : "bin"
  end
end
