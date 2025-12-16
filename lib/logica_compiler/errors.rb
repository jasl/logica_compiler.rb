# frozen_string_literal: true

module LogicaCompiler
  class Error < StandardError; end

  class CommandFailedError < Error
    attr_reader :command

    def initialize(message = nil, command: nil)
      @command = command
      super(message)
    end
  end

  class ConfigurationError < Error; end
  class UnknownQueryError < ConfigurationError; end

  class InstallError < Error; end
  class CompileError < Error; end
  class LogicaError < Error; end
  class WatcherError < Error; end
end
