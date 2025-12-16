# frozen_string_literal: true

require "test_helper"

require "rake"
require "fileutils"
require "tmpdir"
require "stringio"

class InstallTaskTest < Minitest::Test
  def test_install_task_reports_create_for_gitignore_on_fresh_install
    Dir.mktmpdir do |dir|
      Dir.chdir(dir) do
        ENV.delete("FORCE")

        previous_rake = Rake.application
        previous_stdout = $stdout
        previous_stderr = $stderr

        Rake.application = Rake::Application.new
        $stdout = StringIO.new
        $stderr = StringIO.new

        Rake::Task.define_task(:environment)
        load File.expand_path("../lib/logica_compiler/tasks/logica_compiler.rake", __dir__)

        Rake::Task["logica_compiler:install"].invoke

        gitignore = File.read(".gitignore")
        assert_includes gitignore, "/logica/compiled/*"
        assert_includes gitignore, "!/logica/compiled/.keep"
        assert_match(/^create\s+.*\.gitignore/i, $stdout.string)
      ensure
        Rake.application = previous_rake
        $stdout = previous_stdout
        $stderr = previous_stderr
      end
    end
  end

  def test_install_task_generates_initializer_with_config_error_handling
    Dir.mktmpdir do |dir|
      Dir.chdir(dir) do
        ENV.delete("FORCE")

        previous_rake = Rake.application
        previous_stdout = $stdout
        previous_stderr = $stderr

        Rake.application = Rake::Application.new
        $stdout = StringIO.new
        $stderr = StringIO.new

        # The Rails integration task depends on :environment; define a no-op one for this unit test.
        Rake::Task.define_task(:environment)

        load File.expand_path("../lib/logica_compiler/tasks/logica_compiler.rake", __dir__)

        Rake::Task["logica_compiler:install"].invoke

        initializer = File.read("config/initializers/logica_compiler.rb")
        assert_match(/strict = Rails\.env\.production\?/, initializer)
        assert_match(/rescue Errno::ENOENT, Psych::SyntaxError/, initializer)
        assert_match(/Registry\.unavailable/, initializer)
      ensure
        Rake.application = previous_rake
        $stdout = previous_stdout
        $stderr = previous_stderr
      end
    end
  end

  def test_install_task_reports_conflict_and_hints_how_to_resolve
    Dir.mktmpdir do |dir|
      Dir.chdir(dir) do
        ENV.delete("FORCE")

        previous_rake = Rake.application
        previous_stdout = $stdout
        previous_stderr = $stderr

        Rake.application = Rake::Application.new
        $stdout = StringIO.new
        $stderr = StringIO.new

        Rake::Task.define_task(:environment)
        load File.expand_path("../lib/logica_compiler/tasks/logica_compiler.rake", __dir__)

        FileUtils.mkdir_p("bin")
        File.write("bin/logica", "custom\n")

        error = assert_raises(LogicaCompiler::InstallError) { Rake::Task["logica_compiler:install"].invoke }
        assert_match(/conflict\s+.*bin\/logica/i, $stdout.string)
        assert_match(/FORCE=1/i, error.message)
      ensure
        Rake.application = previous_rake
        $stdout = previous_stdout
        $stderr = previous_stderr
      end
    end
  end
end
