# frozen_string_literal: true

require "test_helper"

class VersionTest < Minitest::Test
  def test_has_a_version_number
    refute_nil ::LogicaCompiler::VERSION
  end
end
