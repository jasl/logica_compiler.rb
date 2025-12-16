# frozen_string_literal: true

module LogicaCompiler
  class UnsafeSqlError < StandardError; end

  module SqlSafety
    PROHIBITED_KEYWORDS = %w[
      INSERT UPDATE DELETE MERGE
      CREATE ALTER DROP TRUNCATE
      GRANT REVOKE
    ].freeze

    module_function

    def validate!(sql)
      stripped = strip_leading_comments(sql.to_s).lstrip
      raise UnsafeSqlError, "SQL is empty" if stripped.empty?

      raise UnsafeSqlError, "Unsafe SQL: must start with SELECT/WITH" unless stripped.match?(/\A(?:WITH|SELECT)\b/i)

      sanitized = strip_strings_and_comments(stripped)

      raise UnsafeSqlError, "Unsafe SQL: contains semicolon (multi-statement risk)" if sanitized.include?(";")

      if sanitized.match?(/\b(?:#{PROHIBITED_KEYWORDS.join("|")})\b/i)
        raise UnsafeSqlError, "Unsafe SQL: contains prohibited keyword"
      end

      if sanitized.match?(/\bFOR\s+(?:UPDATE|SHARE|NO\s+KEY\s+UPDATE|KEY\s+SHARE)\b/i)
        raise UnsafeSqlError, "Unsafe SQL: contains row locking clause"
      end

      true
    end

    def strip_leading_comments(sql)
      s = sql.lstrip

      loop do
        if s.start_with?("--")
          s = s.sub(/\A--.*(?:\n|\z)/, "").lstrip
          next
        end

        if s.start_with?("/*")
          s = s.sub(%r{\A/\*.*?\*/}m, "").lstrip
          next
        end

        break
      end

      s
    end

    def strip_strings_and_comments(sql)
      s = sql.to_s
      out = +""

      i = 0
      state = :normal
      dollar_delim = nil

      while i < s.length
        ch = s[i]

        case state
        when :normal
          if ch == "-" && s[i + 1] == "-"
            state = :line_comment
            out << "  "
            i += 2
          elsif ch == "/" && s[i + 1] == "*"
            state = :block_comment
            out << "  "
            i += 2
          elsif ch == "'"
            state = :single_quote
            out << " "
            i += 1
          elsif ch == "\""
            state = :double_quote
            out << " "
            i += 1
          elsif ch == "$"
            delim = parse_dollar_delimiter(s, i)
            if delim
              dollar_delim = delim
              state = :dollar_quote
              out << (" " * delim.length)
              i += delim.length
            else
              out << ch
              i += 1
            end
          else
            out << ch
            i += 1
          end
        when :line_comment
          if ch == "\n"
            state = :normal
            out << "\n"
          else
            out << " "
          end
          i += 1
        when :block_comment
          if ch == "*" && s[i + 1] == "/"
            state = :normal
            out << "  "
            i += 2
          else
            out << " "
            i += 1
          end
        when :single_quote
          if ch == "'"
            if s[i + 1] == "'"
              out << "  "
              i += 2
            else
              state = :normal
              out << " "
              i += 1
            end
          else
            out << " "
            i += 1
          end
        when :double_quote
          if ch == "\""
            if s[i + 1] == "\""
              out << "  "
              i += 2
            else
              state = :normal
              out << " "
              i += 1
            end
          else
            out << " "
            i += 1
          end
        when :dollar_quote
          if dollar_delim && s[i, dollar_delim.length] == dollar_delim
            out << (" " * dollar_delim.length)
            i += dollar_delim.length
            dollar_delim = nil
            state = :normal
          else
            out << " "
            i += 1
          end
        end
      end

      out
    end

    def parse_dollar_delimiter(s, start_index)
      return nil unless s[start_index] == "$"

      j = start_index + 1
      while j < s.length && s[j] != "$"
        return nil unless s[j].match?(/[A-Za-z0-9_]/)

        j += 1
      end

      return nil unless j < s.length && s[j] == "$"

      s[start_index..j]
    end
  end
end
