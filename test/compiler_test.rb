# frozen_string_literal: true

require "test_helper"
require "tmpdir"
require "fileutils"
require "pathname"

class CompilerTest < Minitest::Test
  def test_compile_all_writes_digested_sql_meta_and_manifest
    Dir.mktmpdir do |dir|
      root = Pathname(dir)

      FileUtils.mkdir_p(root.join("logica/programs"))
      FileUtils.mkdir_p(root.join("logica/compiled"))

      program_rel = "logica/programs/user_report.l"
      program_abs = root.join(program_rel)
      program_abs.write(<<~LOGICA)
        UserReport(user_id: 1, value: "a");
      LOGICA

      root.join("logica/config.yml").write(<<~YAML)
        engine: postgres
        output_dir: logica/compiled
        queries:
          user_report:
            program: #{program_rel}
            predicate: UserReport
      YAML

      config = LogicaCompiler::Config.load!("logica/config.yml", root:)
      compiler = LogicaCompiler::Compiler.new(config:)

      compiler.stub(:logica_version, "1.2.3") do
        compiler.stub(:compile_via_cli!, "SELECT 1 AS user_id, 'a' AS value") do
          compiler.compile_all!
        end
      end

      manifest_path = root.join("logica/compiled/manifest.json")
      assert_predicate manifest_path, :exist?

      manifest = LogicaCompiler::Manifest.load(manifest_path)
      entry = manifest.dig("queries", "user_report")
      refute_nil entry

      digest_hex = entry.fetch("digest").delete_prefix("sha256:")
      sql_path = root.join("logica/compiled/user_report-#{digest_hex}.sql")
      meta_path = root.join("logica/compiled/user_report-#{digest_hex}.meta.json")

      assert_predicate sql_path, :exist?
      assert_predicate meta_path, :exist?

      sql = sql_path.read
      assert_match(/-- digest: sha256:/, sql)
      assert_match(/\bSELECT 1\b/, sql)
    end
  end

  def test_compile_one_skips_when_digest_matches_and_force_is_false
    Dir.mktmpdir do |dir|
      root = Pathname(dir)

      FileUtils.mkdir_p(root.join("logica/programs"))
      out_dir = root.join("logica/compiled")
      FileUtils.mkdir_p(out_dir)

      program_rel = "logica/programs/user_report.l"
      root.join(program_rel).write(<<~LOGICA)
        UserReport(user_id: 1, value: "a");
      LOGICA

      root.join("logica/config.yml").write(<<~YAML)
        engine: postgres
        output_dir: logica/compiled
        queries:
          user_report:
            program: #{program_rel}
            predicate: UserReport
      YAML

      config = LogicaCompiler::Config.load!("logica/config.yml", root:)
      compiler = LogicaCompiler::Compiler.new(config:)

      digest_hex = "abc"
      entry = {
        "digest" => "sha256:#{digest_hex}",
        "sql" => "user_report-#{digest_hex}.sql",
        "meta" => "user_report-#{digest_hex}.meta.json",
      }

      out_dir.join(entry.fetch("sql")).write("SELECT 1\n")
      out_dir.join(entry.fetch("meta")).write("{}\n")
      LogicaCompiler::Manifest.write!(
        config.manifest_path,
        LogicaCompiler::Manifest.build(engine: "postgres", logica_version: "1.2.3", queries: { user_report: entry })
      )

      compiler.stub(:compute_digest, digest_hex) do
        compiler.stub(:compile_via_cli!, ->(**) { flunk("should not call Logica CLI when digest matches") }) do
          returned = compiler.compile_one!(name: :user_report, query: config.queries.fetch(:user_report), force: false)
          assert_equal entry, returned
        end
      end
    end
  end

  def test_compile_one_recompiles_when_force_is_true_even_if_digest_matches
    Dir.mktmpdir do |dir|
      root = Pathname(dir)

      FileUtils.mkdir_p(root.join("logica/programs"))
      out_dir = root.join("logica/compiled")
      FileUtils.mkdir_p(out_dir)

      program_rel = "logica/programs/user_report.l"
      root.join(program_rel).write(<<~LOGICA)
        UserReport(user_id: 1, value: "a");
      LOGICA

      root.join("logica/config.yml").write(<<~YAML)
        engine: postgres
        output_dir: logica/compiled
        queries:
          user_report:
            program: #{program_rel}
            predicate: UserReport
      YAML

      config = LogicaCompiler::Config.load!("logica/config.yml", root:)
      compiler = LogicaCompiler::Compiler.new(config:)

      digest_hex = "abc"
      entry = {
        "digest" => "sha256:#{digest_hex}",
        "sql" => "user_report-#{digest_hex}.sql",
        "meta" => "user_report-#{digest_hex}.meta.json",
      }

      out_dir.join(entry.fetch("sql")).write("SELECT 1\n")
      out_dir.join(entry.fetch("meta")).write("{}\n")
      LogicaCompiler::Manifest.write!(
        config.manifest_path,
        LogicaCompiler::Manifest.build(engine: "postgres", logica_version: "1.2.3", queries: { user_report: entry })
      )

      compiler.stub(:compute_digest, digest_hex) do
        compiler.stub(:compile_via_cli!, "SELECT 42 AS user_id") do
          compiler.compile_one!(name: :user_report, query: config.queries.fetch(:user_report), force: true, prune: true)
        end
      end

      sql = out_dir.join(entry.fetch("sql")).read
      assert_match(/-- LogicaCompiler/, sql)
      assert_match(/\bSELECT 42\b/, sql)
    end
  end

  def test_compile_one_prunes_old_digested_artifacts_for_same_query
    Dir.mktmpdir do |dir|
      root = Pathname(dir)

      FileUtils.mkdir_p(root.join("logica/programs"))
      out_dir = root.join("logica/compiled")
      FileUtils.mkdir_p(out_dir)

      program_rel = "logica/programs/user_report.l"
      root.join(program_rel).write(<<~LOGICA)
        UserReport(user_id: 1, value: "a");
      LOGICA

      root.join("logica/config.yml").write(<<~YAML)
        engine: postgres
        output_dir: logica/compiled
        queries:
          user_report:
            program: #{program_rel}
            predicate: UserReport
      YAML

      out_dir.join("user_report-old.sql").write("SELECT 1\n")
      out_dir.join("user_report-old.meta.json").write("{}\n")

      config = LogicaCompiler::Config.load!("logica/config.yml", root:)
      compiler = LogicaCompiler::Compiler.new(config:)

      compiler.stub(:compute_digest, "new") do
        compiler.stub(:logica_version, "1.2.3") do
          compiler.stub(:compile_via_cli!, "SELECT 1 AS user_id, 'a' AS value") do
            compiler.compile_one!(name: :user_report, query: config.queries.fetch(:user_report), force: true, prune: true)
          end
        end
      end

      refute_predicate out_dir.join("user_report-old.sql"), :exist?
      refute_predicate out_dir.join("user_report-old.meta.json"), :exist?
    end
  end

  def test_program_engine_mismatch_raises
    Dir.mktmpdir do |dir|
      root = Pathname(dir)

      FileUtils.mkdir_p(root.join("logica/programs"))
      FileUtils.mkdir_p(root.join("logica/compiled"))

      program_rel = "logica/programs/user_report.l"
      root.join(program_rel).write(<<~LOGICA)
        @Engine("sqlite");
        UserReport(user_id: 1, value: "a");
      LOGICA

      root.join("logica/config.yml").write(<<~YAML)
        engine: postgres
        output_dir: logica/compiled
        queries:
          user_report:
            program: #{program_rel}
            predicate: UserReport
      YAML

      config = LogicaCompiler::Config.load!("logica/config.yml", root:)
      compiler = LogicaCompiler::Compiler.new(config:)

      assert_raises(ArgumentError) do
        compiler.compile_one!(name: :user_report, query: config.queries.fetch(:user_report), force: true, prune: true)
      end
    end
  end

  def test_normalize_sql_keeps_last_select_or_with_from_psql_script
    Dir.mktmpdir do |dir|
      root = Pathname(dir)
      FileUtils.mkdir_p(root.join("logica/compiled"))

      root.join("logica/config.yml").write(<<~YAML)
        engine: postgres
        output_dir: logica/compiled
        queries: {}
      YAML

      config = LogicaCompiler::Config.load!("logica/config.yml", root:)
      compiler = LogicaCompiler::Compiler.new(config:)

      psql_script = <<~SQL
        -- preamble
        SELECT 1 AS x;

        WITH y AS (SELECT 2 AS x)
        SELECT * FROM y;
      SQL

      normalized = compiler.send(:normalize_sql, psql_script)
      assert_match(/\AWITH\b/i, normalized)
      refute_match(/\ASELECT 1\b/i, normalized)
      refute_includes normalized, ";"
    end
  end

  def test_compile_timeout_falls_back_to_default_on_invalid_env
    Dir.mktmpdir do |dir|
      root = Pathname(dir)

      FileUtils.mkdir_p(root.join("logica/programs"))
      FileUtils.mkdir_p(root.join("logica/compiled"))

      program_rel = "logica/programs/user_report.l"
      root.join(program_rel).write(<<~LOGICA)
        UserReport(user_id: 1, value: "a");
      LOGICA

      root.join("logica/config.yml").write(<<~YAML)
        engine: postgres
        output_dir: logica/compiled
        queries:
          user_report:
            program: #{program_rel}
            predicate: UserReport
      YAML

      config = LogicaCompiler::Config.load!("logica/config.yml", root:)
      compiler = LogicaCompiler::Compiler.new(config:)

      with_env("LOGICA_COMPILE_TIMEOUT" => "not-an-integer") do
        compiler.stub(:logica_version, "1.2.3") do
          compiler.stub(:compile_via_cli!, lambda { |program_source:, predicate:, timeout:|
            _ = program_source
            _ = predicate
            assert_equal LogicaCompiler::Compiler::DEFAULT_TIMEOUT, timeout
            "SELECT 1 AS user_id, 'a' AS value"
          }) do
            compiler.compile_one!(name: :user_report, query: config.queries.fetch(:user_report), force: true, prune: true)
          end
        end
      end
    end
  end

  def test_logica_version_returns_pinned_version_from_requirements
    Dir.mktmpdir do |dir|
      root = Pathname(dir)
      FileUtils.mkdir_p(root.join("logica"))

      root.join("logica/requirements.txt").write("logica==9.9.9\n")
      root.join("logica/config.yml").write(<<~YAML)
        engine: postgres
        output_dir: logica/compiled
        queries: {}
      YAML

      config = LogicaCompiler::Config.load!("logica/config.yml", root:)
      compiler = LogicaCompiler::Compiler.new(config:)

      assert_equal "9.9.9", compiler.logica_version
    end
  end

  def test_logica_version_can_be_inferred_from_venv_python_when_available
    Dir.mktmpdir do |dir|
      root = Pathname(dir)

      venv_dir = root.join("tmp/logica_venv")
      FileUtils.mkdir_p(venv_dir.join(venv_bin_dir))

      python = venv_dir.join(venv_bin_dir, "python")
      python.write("#!/usr/bin/env ruby\nputs \"stub\"\n")
      FileUtils.chmod(0o755, python)

      logica = venv_dir.join(venv_bin_dir, "logica")
      logica.write("#!/usr/bin/env ruby\nputs \"stub\"\n")
      FileUtils.chmod(0o755, logica)

      FileUtils.mkdir_p(root.join("logica"))
      root.join("logica/config.yml").write(<<~YAML)
        engine: postgres
        output_dir: logica/compiled
        logica_bin: #{logica}
        queries: {}
      YAML

      config = LogicaCompiler::Config.load!("logica/config.yml", root:)
      compiler = LogicaCompiler::Compiler.new(config:)

      status = Minitest::Mock.new
      status.expect(:success?, true)

      compiler.stub(:run_cmd_with_timeout!, ["1.3.0\n", "", status]) do
        assert_equal "1.3.0", compiler.logica_version
      end
    end
  end

  def test_postgres_engine_alias_is_normalized_to_psql_for_logica
    Dir.mktmpdir do |dir|
      root = Pathname(dir)
      FileUtils.mkdir_p(root.join("logica/compiled"))

      root.join("logica/config.yml").write(<<~YAML)
        engine: postgres
        output_dir: logica/compiled
        queries: {}
      YAML

      config = LogicaCompiler::Config.load!("logica/config.yml", root:)
      compiler = LogicaCompiler::Compiler.new(config:)

      source = <<~LOGICA
        @Engine("postgres");
        Test(x: 1);
      LOGICA

      effective = compiler.send(:ensure_engine_directive, source)
      assert_includes effective, '@Engine("psql");'
    end
  end

  def test_program_engine_psql_is_accepted_when_config_engine_is_postgres
    Dir.mktmpdir do |dir|
      root = Pathname(dir)
      FileUtils.mkdir_p(root.join("logica/compiled"))

      root.join("logica/config.yml").write(<<~YAML)
        engine: postgres
        output_dir: logica/compiled
        queries: {}
      YAML

      config = LogicaCompiler::Config.load!("logica/config.yml", root:)
      compiler = LogicaCompiler::Compiler.new(config:)

      source = <<~LOGICA
        @Engine("psql");
        Test(x: 1);
      LOGICA

      assert_nil compiler.send(:validate_program_engine!, source)
    end
  end

  def test_psql_output_preamble_is_stripped_to_last_select
    Dir.mktmpdir do |dir|
      root = Pathname(dir)
      FileUtils.mkdir_p(root.join("logica/compiled"))

      root.join("logica/config.yml").write(<<~YAML)
        engine: postgres
        output_dir: logica/compiled
        queries: {}
      YAML

      config = LogicaCompiler::Config.load!("logica/config.yml", root:)
      compiler = LogicaCompiler::Compiler.new(config:)

      psql_script = <<~SQL
        -- Initializing PostgreSQL environment.
        set client_min_messages to warning;
        create schema if not exists logica_home;
        DO $$ BEGIN END $$;

        SELECT
          1 AS x;
      SQL

      normalized = compiler.send(:normalize_sql, psql_script)
      assert_match(/\ASELECT\b/i, normalized)
      refute_match(/create schema/i, normalized)
      refute_includes normalized, ";"
    end
  end

  private
end
