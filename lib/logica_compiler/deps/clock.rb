# frozen_string_literal: true

module LogicaCompiler
  module Deps
    class Clock
      def now = Time.now
      def now_utc = Time.now.utc
    end
  end
end
