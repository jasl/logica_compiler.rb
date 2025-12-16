# frozen_string_literal: true

require "bundler/gem_tasks"
require "minitest/test_task"

Minitest::TestTask.create

require "rubocop/rake_task"

RuboCop::RakeTask.new

task default: %i[test rubocop]

desc "Run tests with a lib/ coverage summary (local use; not wired into CI)"
task :coverage do
  ENV["MT_NO_PLUGINS"] = "1"

  require "coverage"
  Coverage.start

  lib_root = File.expand_path("lib", __dir__)
  test_root = File.expand_path("test", __dir__)

  $LOAD_PATH.unshift(lib_root) unless $LOAD_PATH.include?(lib_root)
  $LOAD_PATH.unshift(test_root) unless $LOAD_PATH.include?(test_root)

  # Load all gem library files so untested files show up in the report too.
  Dir[File.join(lib_root, "**/*.rb")].sort.each do |path|
    rel = path.sub("#{lib_root}/", "").sub(/\.rb\z/, "")
    next if rel == "logica_compiler/railtie" # Rails is optional in this gem.

    require rel
  end

  require "test_helper"

  Dir[File.join(test_root, "**/*_test.rb")].sort.each do |path|
    next if path.end_with?("test_helper.rb")

    require path
  end

  Minitest.after_run do
    result = Coverage.result
    lib_prefix = "#{lib_root}#{File::SEPARATOR}"

    rows = []
    result.each do |path, counts|
      next unless path.start_with?(lib_prefix)
      next unless counts.is_a?(Array)

      total = 0
      covered = 0
      counts.each do |c|
        next if c.nil?
        total += 1
        covered += 1 if c.positive?
      end

      pct = total.positive? ? (covered * 100.0 / total) : 0
      rel = path.sub("#{File.expand_path(__dir__)}#{File::SEPARATOR}", "")
      rows << [pct, covered, total, rel]
    end

    rows.sort_by!(&:first)
    puts "\nlib/ coverage by file (low → high):"
    rows.each do |pct, covered, total, rel|
      puts format("%6.1f%%  %4d/%-4d  %s", pct, covered, total, rel)
    end

    total_covered = rows.sum { |r| r[1] }
    total_lines = rows.sum { |r| r[2] }
    total_pct = total_lines.positive? ? (total_covered * 100.0 / total_lines) : 0
    puts format("\nTOTAL: %d/%d (%.1f%%)\n", total_covered, total_lines, total_pct)
  end
end
