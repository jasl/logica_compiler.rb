# frozen_string_literal: true

require "test_helper"
require "tmpdir"
require "fileutils"
require "pathname"

E2E_REQUIRED = ENV["LOGICA_E2E_REQUIRED"].to_s == "1"

begin
  require "active_record"
  require "sqlite3"
  require "logica_compiler/active_record/runner"
rescue LoadError => e
  raise e if E2E_REQUIRED
  # CI for the gem will include these dependencies; allow local runs without them.
end

class SqliteE2eTest < Minitest::Test
  def test_compile_and_run_on_sqlite
    unless defined?(::ActiveRecord) && defined?(::SQLite3)
      return flunk("sqlite3/activerecord not available (LOGICA_E2E_REQUIRED=1)") if E2E_REQUIRED

      skip "sqlite3/activerecord not available"
    end

    Dir.mktmpdir do |dir|
      root = Pathname(dir)

      FileUtils.mkdir_p(root.join("logica/programs"))
      FileUtils.mkdir_p(root.join("logica/compiled"))

      # Minimal program that compiles to a pure SQL relation (no DB tables required).
      program_rel = "logica/programs/user_report.l"
      root.join(program_rel).write(<<~LOGICA)
        @Engine("sqlite");
        UserReport(user_id: 1, value: "a");
        UserReport(user_id: 2, value: "b");
      LOGICA

      root.join("logica/config.yml").write(<<~YAML)
        engine: sqlite
        output_dir: logica/compiled
        logica_bin: #{ENV.fetch("LOGICA_BIN", "logica")}
        queries:
          user_report:
            program: #{program_rel}
            predicate: UserReport
      YAML

      config = LogicaCompiler::Config.load!("logica/config.yml", root:)
      unless logica_available?(config.logica_bin.to_s)
        return flunk("logica CLI not available (expected LOGICA_BIN=logica on CI)") if E2E_REQUIRED

        skip "logica CLI not available"
      end

      compiler = LogicaCompiler::Compiler.new(config:)
      compiler.compile_all!

      registry = LogicaCompiler::Registry.load(manifest_path: config.manifest_path, output_dir: config.output_dir_path,
                                               strict: true)

      ::ActiveRecord::Base.establish_connection(adapter: "sqlite3", database: ":memory:")
      runner = LogicaCompiler::ActiveRecord::Runner.new(registry:, connection_pool: ::ActiveRecord::Base.connection_pool)

      result = runner.exec(:user_report, filters: { user_id: 1 }, statement_timeout: nil)
      assert_equal 1, result.rows.length
      assert_equal [1, "a"], result.rows.first
    end
  end
end
