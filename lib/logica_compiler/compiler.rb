# frozen_string_literal: true

require "digest"
require "fileutils"
require "json"
require "open3"
require "time"
require "timeout"

require_relative "sql_safety"
require_relative "util"

module LogicaCompiler
  class Compiler
    DEFAULT_TIMEOUT = 30

    # User-friendly aliases → Logica CLI engine names.
    # Python Logica uses "psql" as the PostgreSQL engine name (not "postgres").
    ENGINE_ALIASES = {
      "postgres" => "psql",
      "postgresql" => "psql",
      "pg" => "psql",
    }.freeze

    def initialize(config:)
      @config = config
      @logica_version = nil
    end

    def compile_all!(force: false, prune: true)
      version = logica_version
      out_dir = @config.output_dir_path
      FileUtils.mkdir_p(out_dir)

      entries = {}
      @config.queries.each do |name, query|
        entries[name.to_s] = compile_one!(name:, query:, force:, prune:, logica_version: version)
      end

      manifest = Manifest.build(
        engine: @config.engine,
        logica_version: version,
        queries: entries
      )
      Manifest.write!(@config.manifest_path, manifest)
      manifest
    end

    def compile_one!(name:, query:, force: false, prune: true, logica_version: self.logica_version)
      out_dir = @config.output_dir_path
      FileUtils.mkdir_p(out_dir)

      program_path = @config.absolute_path(query.program)
      program_source = File.read(program_path)
      validate_program_engine!(program_source)

      digest_hex = compute_digest(program_source:, predicate: query.predicate, engine: @config.engine, logica_version:)
      digest = "sha256:#{digest_hex}"

      sql_filename = "#{name}-#{digest_hex}.sql"
      meta_filename = "#{name}-#{digest_hex}.meta.json"
      sql_path = out_dir.join(sql_filename)
      meta_path = out_dir.join(meta_filename)

      return existing_entry_for(name:) if !force && entry_exists?(name:, digest_hex:)

      prune_old_artifacts!(name:, keep_digest_hex: digest_hex) if prune

      compiled_sql = compile_via_cli!(program_source:, predicate: query.predicate, timeout: compile_timeout)
      compiled_sql = normalize_sql(compiled_sql)

      sql_with_header = add_sql_header(
        sql: compiled_sql,
        name: name.to_s,
        program: query.program,
        predicate: query.predicate,
        engine: @config.engine,
        digest:
      )
      SqlSafety.validate!(sql_with_header)

      File.write(sql_path, sql_with_header)

      meta = {
        name: name.to_s,
        program: query.program,
        predicate: query.predicate,
        engine: @config.engine,
        compiled_at: Time.now.utc.iso8601,
        compiler: { bin: @config.logica_bin, version: logica_version },
        digest: digest,
      }
      File.write(meta_path, "#{JSON.pretty_generate(meta)}\n")

      { "digest" => digest, "sql" => sql_filename, "meta" => meta_filename }
    end

    def logica_version
      return @logica_version if @logica_version

      pinned = @config.pinned_logica_version
      return (@logica_version = pinned) if pinned && !pinned.to_s.strip.empty?

      # If LOGICA_BIN points to a venv-installed executable, infer the venv python and ask pip metadata.
      bin = @config.logica_bin.to_s
      if bin.include?(File::SEPARATOR) || bin.start_with?(".")
        venv_dir = File.expand_path("..", File.dirname(bin))
        python = File.join(venv_dir, Util.venv_bin_dir, "python")
        if File.executable?(python)
          stdout, _stderr, status =
            run_cmd_with_timeout!(
              [python, "-c", "import importlib.metadata as m; print(m.version('logica'))"],
              stdin_data: nil,
              timeout: 5
            )
          version = stdout.to_s.strip
          return (@logica_version = version) if status.success? && !version.empty?
        end
      end

      @logica_version = "unknown"
    rescue StandardError
      @logica_version = @config.pinned_logica_version || "unknown"
    end

    private

    def compile_timeout
      Integer(ENV.fetch("LOGICA_COMPILE_TIMEOUT", DEFAULT_TIMEOUT))
    rescue ArgumentError
      DEFAULT_TIMEOUT
    end

    def entry_exists?(name:, digest_hex:)
      entry = existing_entry_for(name:)
      return false unless entry
      return false unless entry["digest"].to_s == "sha256:#{digest_hex}"

      out_dir = @config.output_dir_path
      sql_file = entry["sql"].to_s
      meta_file = entry["meta"].to_s
      return false if sql_file.empty? || meta_file.empty?

      out_dir.join(sql_file).exist? && out_dir.join(meta_file).exist?
    end

    def existing_entry_for(name:)
      manifest = Manifest.load(@config.manifest_path)
      manifest.fetch("queries", {}).fetch(name.to_s)
    rescue Errno::ENOENT, KeyError, JSON::ParserError
      nil
    end

    def compute_digest(program_source:, predicate:, engine:, logica_version:)
      Digest::SHA256.hexdigest([program_source, predicate, engine, logica_version].join("\n"))
    end

    def normalize_sql(sql)
      sql = sql.to_s
      sql = extract_main_query_from_psql_script(sql) if logica_engine == "psql"
      sql.strip.sub(/;\s*\z/, "")
    end

    def validate_program_engine!(program_source)
      declared = program_source.match(/@Engine\(\s*["']([^"']+)["']\s*\)\s*;/i)&.captures&.first
      return if declared.nil?

      return if canonical_engine(declared) == logica_engine

      raise ArgumentError, "Program @Engine(#{declared.inspect}) does not match config engine #{@config.engine.inspect}"
    end

    def compile_via_cli!(program_source:, predicate:, timeout:)
      effective_source = ensure_engine_directive(program_source)
      cmd = [@config.logica_bin, "-", "print", predicate.to_s]
      stdout, stderr, status = run_cmd_with_timeout!(cmd, stdin_data: effective_source, timeout:)
      raise "Logica compile failed: #{stderr}" unless status.success?

      stdout
    end

    def ensure_engine_directive(program_source)
      engine = logica_engine

      # If present, normalize to the canonical Logica engine name (e.g., postgres -> psql).
      if program_source.match?(/@Engine\(\s*["'][^"']+["']\s*\)\s*;/i)
        return program_source.sub(/@Engine\(\s*(["'])([^"']+)\1\s*\)\s*;/i) do
          quote = Regexp.last_match(1)
          "@Engine(#{quote}#{engine}#{quote});"
        end
      end

      "@Engine(\"#{engine}\");\n#{program_source}"
    end

    def canonical_engine(engine)
      value = engine.to_s.strip
      return "" if value.empty?

      down = value.downcase
      ENGINE_ALIASES.fetch(down, down)
    end

    def logica_engine
      canonical_engine(@config.engine)
    end

    def extract_main_query_from_psql_script(sql)
      # Logica's psql engine prints a multi-statement script (preamble + final query).
      # Our runner expects a single SELECT/WITH statement, so keep only the last statement
      # that starts with SELECT/WITH, ignoring semicolons inside strings/comments/dollar-quotes.
      sanitized = SqlSafety.strip_strings_and_comments(sql)

      statement_starts = [0]
      sanitized.to_enum(:scan, /;/).each do
        statement_starts << Regexp.last_match.end(0)
      end

      last = nil
      statement_starts.each do |start|
        i = start
        i += 1 while i < sanitized.length && sanitized[i].match?(/\s/)
        next if i >= sanitized.length

        last = i if sanitized[i..].match?(/\A(?:WITH|SELECT)\b/i)
      end

      last ? sql[last..] : sql
    end

    def add_sql_header(sql:, name:, program:, predicate:, engine:, digest:)
      header = <<~SQL
        -- LogicaCompiler
        -- name: #{name}
        -- program: #{program}
        -- predicate: #{predicate}
        -- engine: #{engine}
        -- digest: #{digest}
        -- compiled_at: #{Time.now.utc.iso8601}
      SQL

      "#{header}\n#{sql.strip}\n"
    end

    def prune_old_artifacts!(name:, keep_digest_hex:)
      out_dir = @config.output_dir_path

      Dir.glob(out_dir.join("#{name}-*.sql").to_s).each do |path|
        next if path.end_with?("-#{keep_digest_hex}.sql")

        FileUtils.rm_f(path)
      end

      Dir.glob(out_dir.join("#{name}-*.meta.json").to_s).each do |path|
        next if path.end_with?("-#{keep_digest_hex}.meta.json")

        FileUtils.rm_f(path)
      end
    end

    def run_cmd_with_timeout!(cmd, stdin_data:, timeout:)
      stdout_str = +""
      stderr_str = +""

      Open3.popen3(*cmd) do |stdin, stdout, stderr, wait_thr|
        stdin.binmode
        stdout.binmode
        stderr.binmode

        stdin.write(stdin_data) if stdin_data
        stdin.close

        out_reader = Thread.new { stdout_str << stdout.read.to_s }
        err_reader = Thread.new { stderr_str << stderr.read.to_s }

        status = nil
        begin
          status = Timeout.timeout(timeout) { wait_thr.value }
        rescue Timeout::Error
          terminate_process(wait_thr.pid)
          raise
        ensure
          out_reader.join
          err_reader.join
        end

        [stdout_str, stderr_str, status]
      end
    rescue Timeout::Error
      raise Timeout::Error, "Command timed out after #{timeout}s: #{cmd.join(" ")}"
    end

    def terminate_process(pid)
      Process.kill("TERM", pid)
      Timeout.timeout(2) { Process.wait(pid) }
    rescue Errno::ESRCH, Errno::ECHILD, Timeout::Error
      begin
        Process.kill("KILL", pid)
      rescue Errno::ESRCH
        nil
      end
    end
  end
end
