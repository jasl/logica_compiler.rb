# frozen_string_literal: true

module LogicaCompiler
  module Deps
    class Sleeper
      def sleep(duration = nil)
        duration.nil? ? Kernel.sleep : Kernel.sleep(duration)
      end
    end
  end
end
