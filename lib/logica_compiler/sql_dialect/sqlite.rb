# frozen_string_literal: true

module LogicaCompiler
  module SqlDialect
    class Sqlite
      def placeholder(_index) = "?"

      def statement_timeout_sql(_connection, _timeout)
        nil
      end
    end
  end
end
