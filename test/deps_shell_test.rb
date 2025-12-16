# frozen_string_literal: true

require "test_helper"
require "rbconfig"

require "logica_compiler/deps/shell"

class DepsShellTest < Minitest::Test
  def test_system_bang_raises_on_failure
    shell = LogicaCompiler::Deps::Shell.new
    ruby = RbConfig.ruby

    assert shell.system!(ruby, "-e", "exit 0")
    assert_raises(LogicaCompiler::Error) { shell.system!(ruby, "-e", "exit 1") }
  end

  def test_capture_bang_returns_stdout_and_raises_on_nonzero
    shell = LogicaCompiler::Deps::Shell.new
    ruby = RbConfig.ruby

    out = shell.capture!(ruby, "-e", "STDOUT.write('ok')")
    assert_equal "ok", out

    error = assert_raises(LogicaCompiler::Error) { shell.capture!(ruby, "-e", "STDERR.write('no'); exit 1") }
    assert_equal "no", error.message
  end
end
