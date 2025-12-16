# frozen_string_literal: true

require "active_record"

require_relative "../sql_dialect/postgres"
require_relative "../sql_dialect/sqlite"

module LogicaCompiler
  module ActiveRecord
    class Runner
      DEFAULT_STATEMENT_TIMEOUT_MS = 3000

      def initialize(registry:, connection: nil, connection_pool: ::ActiveRecord::Base.connection_pool, dialect: nil)
        @registry = registry
        @connection = connection
        @connection_pool = connection_pool
        @dialect = dialect
      end

      def exec(name, filters: {}, limit: nil, statement_timeout: DEFAULT_STATEMENT_TIMEOUT_MS)
        return exec_with_connection(@connection, name, filters:, limit:, statement_timeout:) if @connection

        @connection_pool.with_connection do |conn|
          exec_with_connection(conn, name, filters:, limit:, statement_timeout:)
        end
      end

      private

      def exec_with_connection(conn, name, filters:, limit:, statement_timeout:)
        dialect = @dialect || dialect_for(conn)
        sql, binds = wrap_sql(@registry.sql(name), filters:, limit:, connection: conn, dialect:)
        label = "Logica/#{name}"

        timeout = format_statement_timeout(statement_timeout)
        timeout_sql = timeout && dialect.statement_timeout_sql(conn, timeout)

        return conn.exec_query(sql, label, binds) unless timeout_sql

        conn.transaction do
          conn.execute(timeout_sql)
          conn.exec_query(sql, label, binds)
        end
      end

      def dialect_for(conn)
        adapter = conn.adapter_name.to_s.downcase
        return SqlDialect::Sqlite.new if adapter.include?("sqlite")

        SqlDialect::Postgres.new
      end

      def wrap_sql(base_sql, filters:, limit:, connection:, dialect:)
        where_clauses = []
        binds = []
        idx = 1

        filters.each do |key, value|
          column = key.to_s
          raise ArgumentError, "Invalid filter column: #{column.inspect}" unless column.match?(/\A[a-z_][a-z0-9_]*\z/i)

          where_clauses << "t.#{connection.quote_column_name(column)} = #{dialect.placeholder(idx)}"
          binds << ::ActiveRecord::Relation::QueryAttribute.new(
            column,
            value,
            ::ActiveRecord::Type::Value.new
          )
          idx += 1
        end

        base_sql = base_sql.to_s.strip.sub(/;\s*\z/, "")
        sql = +"SELECT * FROM (#{base_sql}) AS t"
        sql << " WHERE " << where_clauses.join(" AND ") unless where_clauses.empty?
        sql << " LIMIT #{Integer(limit)}" if limit

        [sql, binds]
      end

      def format_statement_timeout(value)
        return nil if value.nil?
        return "#{Integer(value)}ms" if value.is_a?(Integer) || value.to_s.match?(/\A\d+\z/)

        value.to_s
      rescue ArgumentError
        nil
      end
    end
  end
end
