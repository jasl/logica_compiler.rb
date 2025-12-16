# frozen_string_literal: true

module LogicaCompiler
  module SqlDialect
    class Postgres
      def placeholder(index) = "$#{index}"

      def statement_timeout_sql(connection, timeout)
        "SET LOCAL statement_timeout = #{connection.quote(timeout)}"
      end
    end
  end
end
