# frozen_string_literal: true

require "test_helper"
require "tmpdir"
require "fileutils"

class RegistryTest < Minitest::Test
  def test_loads_manifest_and_returns_sql_by_name
    Dir.mktmpdir do |dir|
      out_dir = File.join(dir, "compiled")
      FileUtils.mkdir_p(out_dir)

      sql_file = "user_report-abc.sql"
      meta_file = "user_report-abc.meta.json"
      File.write(File.join(out_dir, sql_file), "SELECT 1\n")
      File.write(File.join(out_dir, meta_file), "{}\n")

      manifest_path = File.join(out_dir, "manifest.json")
      manifest =
        LogicaCompiler::Manifest.build(
          engine: "postgres",
          logica_version: "1.2.3",
          queries: {
            user_report: { "digest" => "sha256:abc", "sql" => sql_file, "meta" => meta_file },
          }
        )
      LogicaCompiler::Manifest.write!(manifest_path, manifest)

      registry = LogicaCompiler::Registry.load(manifest_path:, output_dir: out_dir, strict: true)

      assert_equal "SELECT 1", registry.sql(:user_report).strip
      assert_equal "sha256:abc", registry.entry(:user_report).fetch("digest")
    end
  end

  def test_invalid_manifest_yields_helpful_error_in_non_strict_mode
    Dir.mktmpdir do |dir|
      out_dir = File.join(dir, "compiled")
      FileUtils.mkdir_p(out_dir)

      manifest_path = File.join(out_dir, "manifest.json")
      File.write(manifest_path, "{not-json")

      registry = LogicaCompiler::Registry.load(manifest_path:, output_dir: out_dir, strict: false)
      error = assert_raises(LogicaCompiler::Registry::MissingManifestError) { registry.sql(:anything) }
      assert_match(/Invalid Logica manifest/, error.message)
      assert_match(%r{bin/logica compile}, error.message)
    end
  end

  def test_missing_manifest_raises_in_strict_mode
    assert_raises(LogicaCompiler::Registry::MissingManifestError) do
      LogicaCompiler::Registry.load(manifest_path: "/nope/manifest.json", output_dir: "/nope", strict: true)
    end
  end

  def test_missing_manifest_yields_helpful_error_in_non_strict_mode
    registry = LogicaCompiler::Registry.load(manifest_path: "/nope/manifest.json", output_dir: "/nope", strict: false)

    error = assert_raises(LogicaCompiler::Registry::MissingManifestError) { registry.sql(:anything) }
    assert_match(%r{bin/logica compile}, error.message)
  end
end
