# frozen_string_literal: true

require "open3"

module LogicaCompiler
  module Deps
    class Shell
      def system(*args)
        Kernel.system(*args)
      end

      def system!(*args)
        ok = system(*args)
        raise CommandFailedError.new("Command failed: #{args.join(" ")}", command: args.join(" ")) unless ok

        true
      end

      def capture3(*args)
        Open3.capture3(*args)
      end

      def capture!(*args)
        out, err, status = capture3(*args)
        raise CommandFailedError.new(err.to_s, command: args.join(" ")) unless status.success?

        out
      end
    end
  end
end
