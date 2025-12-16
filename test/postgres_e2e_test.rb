# frozen_string_literal: true

require "test_helper"
require "tmpdir"
require "fileutils"
require "pathname"

class PostgresE2eTest < Minitest::Test
  def test_compile_on_postgres_engine_alias
    e2e_required = ENV["LOGICA_E2E_REQUIRED"].to_s == "1"

    Dir.mktmpdir do |dir|
      root = Pathname(dir)

      FileUtils.mkdir_p(root.join("logica/programs"))
      FileUtils.mkdir_p(root.join("logica/compiled"))

      # Program declares @Engine("postgres") (alias). The Python Logica CLI expects @Engine("psql").
      program_rel = "logica/programs/user_report.l"
      root.join(program_rel).write(<<~LOGICA)
        @Engine("postgres");
        UserReport(user_id: 1, value: "a");
      LOGICA

      root.join("logica/config.yml").write(<<~YAML)
        engine: postgres
        output_dir: logica/compiled
        logica_bin: #{ENV.fetch("LOGICA_BIN", "logica")}
        queries:
          user_report:
            program: #{program_rel}
            predicate: UserReport
      YAML

      config = LogicaCompiler::Config.load!("logica/config.yml", root:)
      unless logica_available?(config.logica_bin.to_s)
        return flunk("logica CLI not available (LOGICA_E2E_REQUIRED=1)") if e2e_required

        skip "logica CLI not available"
      end

      compiler = LogicaCompiler::Compiler.new(config:)
      manifest = compiler.compile_all!

      entry = manifest.dig("queries", "user_report")
      refute_nil entry

      sql_path = config.output_dir_path.join(entry.fetch("sql"))
      assert_predicate sql_path, :exist?

      sql = sql_path.read
      refute_match(/Unrecognized engine/i, sql)
      refute_match(/Initializing PostgreSQL environment/i, sql)
      assert_match(/\bSELECT\b/i, sql)
    end
  end
end
