# frozen_string_literal: true

require "test_helper"
require "tmpdir"

class ManifestTest < Minitest::Test
  def test_build_write_load_roundtrip
    Dir.mktmpdir do |dir|
      path = File.join(dir, "manifest.json")

      manifest =
        LogicaCompiler::Manifest.build(
          engine: "postgres",
          logica_version: "1.2.3",
          queries: {
            user_report: {
              "digest" => "sha256:abc",
              "sql" => "user_report-abc.sql",
              "meta" => "user_report-abc.meta.json",
            },
          }
        )

      LogicaCompiler::Manifest.write!(path, manifest)
      loaded = LogicaCompiler::Manifest.load(path)

      assert_equal manifest["version"], loaded["version"]
      assert_equal "postgres", loaded["engine"]
      assert_equal "1.2.3", loaded.dig("logica", "version")
      assert_equal "user_report-abc.sql", loaded.dig("queries", "user_report", "sql")
    end
  end
end
