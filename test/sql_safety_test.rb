# frozen_string_literal: true

require "test_helper"

class SqlSafetyTest < Minitest::Test
  def test_accepts_select_with_leading_comments
    sql = <<~SQL
      -- header
      /* block */
      SELECT 1
    SQL

    assert LogicaCompiler::SqlSafety.validate!(sql)
  end

  def test_rejects_empty_sql
    assert_raises(LogicaCompiler::UnsafeSqlError) { LogicaCompiler::SqlSafety.validate!("") }
    assert_raises(LogicaCompiler::UnsafeSqlError) { LogicaCompiler::SqlSafety.validate!("   \n\t") }
  end

  def test_rejects_sql_that_is_only_comments
    assert_raises(LogicaCompiler::UnsafeSqlError) { LogicaCompiler::SqlSafety.validate!("-- just a comment\n") }
    assert_raises(LogicaCompiler::UnsafeSqlError) { LogicaCompiler::SqlSafety.validate!("/* just a comment */") }
    assert_raises(LogicaCompiler::UnsafeSqlError) do
      LogicaCompiler::SqlSafety.validate!(<<~SQL)
        -- line
        /* block */
      SQL
    end
  end

  def test_accepts_with_queries
    sql = "WITH x AS (SELECT 1) SELECT * FROM x"
    assert LogicaCompiler::SqlSafety.validate!(sql)
  end

  def test_rejects_semicolons
    sql = "SELECT 1; SELECT 2"
    assert_raises(LogicaCompiler::UnsafeSqlError) { LogicaCompiler::SqlSafety.validate!(sql) }
  end

  def test_allows_semicolons_and_keywords_inside_string_literals
    sql = "SELECT ';DROP TABLE users;' AS s"
    assert LogicaCompiler::SqlSafety.validate!(sql)
  end

  def test_allows_semicolons_and_keywords_inside_dollar_quoted_strings
    sql = "SELECT $$;DROP TABLE users;$$ AS s"
    assert LogicaCompiler::SqlSafety.validate!(sql)

    sql = "SELECT $tag$;DROP TABLE users;$tag$ AS s"
    assert LogicaCompiler::SqlSafety.validate!(sql)
  end

  def test_allows_prohibited_keywords_inside_double_quoted_identifiers
    sql = 'SELECT "DROP" AS keyword_identifier'
    assert LogicaCompiler::SqlSafety.validate!(sql)

    sql = 'SELECT "a""b""DELETE" AS tricky_identifier'
    assert LogicaCompiler::SqlSafety.validate!(sql)
  end

  def test_allows_semicolons_inside_comments
    sql = "SELECT 1 /* ; DROP TABLE users; */"
    assert LogicaCompiler::SqlSafety.validate!(sql)

    sql = "SELECT 1 -- ; DROP TABLE users;\n"
    assert LogicaCompiler::SqlSafety.validate!(sql)
  end

  def test_rejects_row_locking_clauses
    sql = "SELECT * FROM users FOR UPDATE"
    assert_raises(LogicaCompiler::UnsafeSqlError) { LogicaCompiler::SqlSafety.validate!(sql) }
  end

  def test_rejects_row_locking_clause_variants
    sql = "SELECT * FROM users FOR NO KEY UPDATE"
    assert_raises(LogicaCompiler::UnsafeSqlError) { LogicaCompiler::SqlSafety.validate!(sql) }

    sql = "SELECT * FROM users FOR KEY SHARE"
    assert_raises(LogicaCompiler::UnsafeSqlError) { LogicaCompiler::SqlSafety.validate!(sql) }
  end
end
