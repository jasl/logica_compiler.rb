# frozen_string_literal: true

require "erb"
require "fileutils"
require "pathname"
require "yaml"

module LogicaCompiler
  class Installer
    PINNED_LOGICA_VERSION = "1.3.1415926535897"

    DEFAULT_ENGINE = "postgres"
    DEFAULT_OUTPUT_DIR = "logica/compiled"

    SAMPLE_PROGRAM_REL = "logica/programs/hello_world.l"
    SAMPLE_QUERY_NAME = "hello_world"
    SAMPLE_PREDICATE = "Greet"

    def initialize(root:, force: false, stdout: $stdout, stderr: $stderr)
      @root = Pathname(root)
      @force = !!force
      @stdout = stdout
      @stderr = stderr
      @conflicts = []
    end

    def run!
      ensure_dir(@root.join("logica/programs"))
      ensure_dir(@root.join("logica/compiled"))

      ensure_file(@root.join("logica/programs/.keep"), "", mode: nil)
      ensure_file(@root.join("logica/compiled/.keep"), "", mode: nil)

      ensure_template(@root.join(SAMPLE_PROGRAM_REL), "hello_world.l", mode: nil)
      ensure_config_yml
      ensure_requirements
      ensure_gitignore_block
      ensure_template(@root.join("bin/logica"), "bin_logica", mode: 0o755)
      ensure_template(@root.join("config/initializers/logica_compiler.rb"), "initializer.rb", mode: nil)

      if @conflicts.any?
        @stderr.puts "\nConflicts detected. No files were overwritten."
        @stderr.puts @conflicts.map { |p| "  - #{p}" }.join("\n")
        @stderr.puts "\nHow to resolve:"
        @stderr.puts "  - Re-run with FORCE=1 to overwrite conflicting files"
        @stderr.puts "  - Or manually merge the templates and re-run"
        @stderr.puts "Template source: #{template_root}"
        raise "LogicaCompiler install aborted due to conflicts (FORCE=1 to overwrite)."
      end

      say("done", "Installed LogicaCompiler integration into #{@root}")
      say("next", "bin/logica install")
      say("next", "bin/logica compile")
      true
    end

    private

    def template_root
      Pathname(__dir__).join("templates")
    end

    def template_vars
      {
        engine: DEFAULT_ENGINE,
        output_dir: DEFAULT_OUTPUT_DIR,
        sample_program_rel: SAMPLE_PROGRAM_REL,
        sample_query_name: SAMPLE_QUERY_NAME,
        sample_predicate: SAMPLE_PREDICATE,
        pinned_logica_version: PINNED_LOGICA_VERSION,
      }
    end

    def render_template(name)
      path = template_root.join("#{name}.erb")
      ERB.new(path.read, trim_mode: "-").result_with_hash(template_vars)
    end

    def ensure_dir(path)
      path = Pathname(path)
      return say("exist", path.to_s) if path.exist?

      FileUtils.mkdir_p(path)
      say("create", path.to_s)
    end

    def ensure_template(dest, template_name, mode:)
      content = render_template(template_name)
      ensure_file(dest, content, mode:)
    end

    def ensure_file(dest, content, mode:)
      dest = Pathname(dest)

      if dest.exist?
        existing = dest.read
        return say("identical", dest.to_s) if existing == content

        if @force
          write_file(dest, content, mode:)
          return say("force", dest.to_s)
        end

        say("conflict", dest.to_s)
        @conflicts << dest.to_s
        return :conflict
      end

      write_file(dest, content, mode:)
      say("create", dest.to_s)
      :create
    end

    def write_file(dest, content, mode:)
      FileUtils.mkdir_p(dest.dirname)
      dest.write(content)
      File.chmod(mode, dest.to_s) if mode
    end

    def ensure_config_yml
      path = @root.join("logica/config.yml")

      if !path.exist? || @force
        return ensure_template(path, "config.yml", mode: nil)
      end

      begin
        data = YAML.safe_load(path.read, permitted_classes: [], aliases: false) || {}
        data = data.to_h
      rescue StandardError => e
        say("conflict", path.to_s)
        @stderr.puts "Could not parse #{path} (#{e.class}: #{e.message}). Please merge manually or re-run with FORCE=1."
        @conflicts << path.to_s
        return :conflict
      end

      changed = false
      unless data["engine"]
        data["engine"] = DEFAULT_ENGINE
        changed = true
      end
      unless data["output_dir"]
        data["output_dir"] = DEFAULT_OUTPUT_DIR
        changed = true
      end

      queries = data["queries"]
      queries = {} unless queries.is_a?(Hash)
      unless queries.key?(SAMPLE_QUERY_NAME)
        queries[SAMPLE_QUERY_NAME] = { "program" => SAMPLE_PROGRAM_REL, "predicate" => SAMPLE_PREDICATE }
        data["queries"] = queries
        changed = true
      end

      return say("identical", path.to_s) unless changed

      yaml = YAML.dump(data)
      yaml = yaml.sub(/\A---\s*\n/, "")
      yaml << "\n" unless yaml.end_with?("\n")
      write_file(path, yaml, mode: nil)
      say("update", path.to_s)
      :update
    end

    def ensure_requirements
      path = @root.join("logica/requirements.txt")
      desired = render_template("requirements.txt")

      if path.exist? && !@force
        if path.read.include?("logica==")
          return say("identical", path.to_s)
        end

        say("conflict", path.to_s)
        @stderr.puts "requirements.txt exists but does not pin logica. Add:\n  #{desired.strip}\nOr re-run with FORCE=1."
        @conflicts << path.to_s
        return :conflict
      end

      ensure_file(path, desired, mode: nil)
    end

    def ensure_gitignore_block
      path = @root.join(".gitignore")
      existing = path.exist? ? path.read : +""

      block = render_template("gitignore_block")
      return say("identical", path.to_s) if existing.include?("/logica/compiled/*")

      updated = existing.dup
      updated << "\n" unless updated.end_with?("\n") || updated.empty?
      updated << block

      write_file(path, updated, mode: nil)
      say(path.exist? ? "update" : "create", path.to_s)
      :update
    end

    def say(status, message)
      @stdout.puts format("%-10s %s", status, message)
    end
  end
end
