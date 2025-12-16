# frozen_string_literal: true

$LOAD_PATH.unshift File.expand_path("../lib", __dir__)
require "logica_compiler"
require "logica_compiler/deps/env"

require "minitest/autorun"
require "minitest/mock"

module TestHelpers
  def with_env(updates, &block)
    LogicaCompiler::Deps::Env.new.with_temp(updates, &block)
  end

  def venv_bin_dir
    LogicaCompiler::Util.venv_bin_dir
  end

  def logica_available?(bin)
    return File.executable?(bin) if LogicaCompiler::Util.path_like?(bin)

    ENV.fetch("PATH", "").split(File::PATH_SEPARATOR).any? do |dir|
      path = File.join(dir, bin)
      File.file?(path) && File.executable?(path)
    end
  end
end

class Minitest::Test
  include TestHelpers
end
