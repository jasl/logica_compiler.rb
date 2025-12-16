# frozen_string_literal: true

require "test_helper"

RUNNER_DEPS_AVAILABLE =
  begin
    require "active_record"
    require "sqlite3"
    require "logica_compiler/active_record/runner"
    true
  rescue LoadError
    false
  end

class RunnerTest < Minitest::Test
  def test_rejects_invalid_filter_column_names
    skip "activerecord/sqlite3 not available" unless RUNNER_DEPS_AVAILABLE

    registry = Object.new
    def registry.sql(_name) = "SELECT 1 AS user_id"

    ::ActiveRecord::Base.establish_connection(adapter: "sqlite3", database: ":memory:")
    runner = LogicaCompiler::ActiveRecord::Runner.new(registry:, connection_pool: ::ActiveRecord::Base.connection_pool)

    assert_raises(ArgumentError) do
      runner.exec(:any, filters: { "user_id; DROP TABLE users" => 1 }, statement_timeout: nil)
    end
  end

  def test_exec_applies_filters_and_limit_on_sqlite
    skip "activerecord/sqlite3 not available" unless RUNNER_DEPS_AVAILABLE

    registry = Object.new
    def registry.sql(_name)
      <<~SQL
        SELECT 1 AS user_id, 'a' AS value
        UNION ALL SELECT 2 AS user_id, 'b' AS value
        UNION ALL SELECT 3 AS user_id, 'c' AS value
      SQL
    end

    ::ActiveRecord::Base.establish_connection(adapter: "sqlite3", database: ":memory:")
    runner = LogicaCompiler::ActiveRecord::Runner.new(registry:, connection_pool: ::ActiveRecord::Base.connection_pool)

    filtered = runner.exec(:user_report, filters: { user_id: 2 }, statement_timeout: nil)
    assert_equal 1, filtered.rows.length
    assert_equal [2, "b"], filtered.rows.first

    limited = runner.exec(:user_report, limit: 2, statement_timeout: nil)
    assert_equal 2, limited.rows.length
  end

  def test_format_statement_timeout
    skip "activerecord/sqlite3 not available" unless RUNNER_DEPS_AVAILABLE

    registry = Object.new
    def registry.sql(_name) = "SELECT 1"

    runner = LogicaCompiler::ActiveRecord::Runner.new(registry:, connection_pool: nil)

    assert_nil runner.send(:format_statement_timeout, nil)
    assert_equal "123ms", runner.send(:format_statement_timeout, 123)
    assert_equal "456ms", runner.send(:format_statement_timeout, "456")
    assert_equal "1s", runner.send(:format_statement_timeout, "1s")
  end

  def test_exec_wraps_in_transaction_when_timeout_sql_is_present
    skip "activerecord/sqlite3 not available" unless RUNNER_DEPS_AVAILABLE

    registry = Object.new
    def registry.sql(_name) = "SELECT 1 AS x"

    conn_class = Class.new do
      attr_reader :executed, :queries, :transactions

      def initialize
        @executed = []
        @queries = []
        @transactions = 0
      end

      def quote_column_name(name) = name.to_s
      def quote(value) = "'#{value}'"

      def exec_query(sql, label, binds)
        @queries << [sql, label, binds]
        :ok
      end

      def execute(sql)
        @executed << sql
      end

      def transaction
        @transactions += 1
        yield
      end
    end

    conn = conn_class.new
    dialect = LogicaCompiler::SqlDialect::Postgres.new
    runner = LogicaCompiler::ActiveRecord::Runner.new(registry:, connection: conn, connection_pool: nil, dialect:)

    result = runner.exec(:any, statement_timeout: 10)
    assert_equal :ok, result
    assert_equal 1, conn.transactions
    assert_equal 1, conn.executed.length
    assert_match(/SET LOCAL statement_timeout/, conn.executed.first)
    assert_equal 1, conn.queries.length
  end

  def test_exec_skips_transaction_when_statement_timeout_is_nil
    skip "activerecord/sqlite3 not available" unless RUNNER_DEPS_AVAILABLE

    registry = Object.new
    def registry.sql(_name) = "SELECT 1 AS x"

    conn_class = Class.new do
      attr_reader :queries, :transactions, :executed

      def initialize
        @queries = []
        @transactions = 0
        @executed = []
      end

      def quote_column_name(name) = name.to_s
      def quote(value) = "'#{value}'"

      def exec_query(sql, label, binds)
        @queries << [sql, label, binds]
        :ok
      end

      def execute(sql)
        @executed << sql
      end

      def transaction
        @transactions += 1
        yield
      end
    end

    conn = conn_class.new
    dialect = LogicaCompiler::SqlDialect::Postgres.new
    runner = LogicaCompiler::ActiveRecord::Runner.new(registry:, connection: conn, connection_pool: nil, dialect:)

    result = runner.exec(:any, statement_timeout: nil)
    assert_equal :ok, result
    assert_equal 0, conn.transactions
    assert_empty conn.executed
    assert_equal 1, conn.queries.length
  end
end
