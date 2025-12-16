# frozen_string_literal: true

module LogicaCompiler
  module Util
    module_function

    def venv_bin_dir
      Gem.win_platform? ? "Scripts" : "bin"
    end

    def command_candidates(cmd)
      cmd = cmd.to_s
      candidates = [cmd]
      return candidates unless Gem.win_platform? && File.extname(cmd).empty?

      pathext = ENV.fetch("PATHEXT", "").split(";").reject(&:empty?)
      pathext = %w[.exe .bat .cmd] if pathext.empty?
      pathext.map { |ext| "#{cmd}#{ext}" }
    end

    def executable_file?(path)
      File.file?(path) && File.executable?(path)
    end

    def find_executable_in_dir(dir, cmd)
      dir = dir.to_s
      command_candidates(cmd).each do |candidate|
        path = File.join(dir, candidate)
        return path if executable_file?(path)
      end
      nil
    end

    def which(cmd)
      ENV.fetch("PATH", "").split(File::PATH_SEPARATOR).each do |dir|
        path = find_executable_in_dir(dir, cmd)
        return path if path
      end
      nil
    end
  end
end
