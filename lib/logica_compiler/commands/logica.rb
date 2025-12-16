# frozen_string_literal: true

require "digest"
require "fileutils"
require "pathname"

require_relative "base"

module LogicaCompiler
  module Commands
    class Logica < Base
      DEFAULT_PYTHON = "python3"

      def ensure_available!(config, allow_install:)
        bin = config.logica_bin.to_s

        if Util.path_like?(bin)
          return if File.executable?(bin)

          if allow_install && bin == default_venv_logica_path(config).to_s
            install_venv_logica!(config)
            return if File.executable?(bin)
          end

          raise LogicaError, "Logica CLI not found: #{bin.inspect}"
        end

        return if which.call(bin)

        raise LogicaError, "Logica CLI #{bin.inspect} not found on PATH. Run `bin/logica install` or set LOGICA_BIN."
      end

      def default_venv_logica_path(config)
        config.root.join("tmp/logica_venv", Util.venv_bin_dir, "logica")
      end

      def install_venv_logica!(config)
        python = env.fetch("LOGICA_PYTHON", DEFAULT_PYTHON)
        requirements = Pathname(env.fetch("LOGICA_REQUIREMENTS", config.requirements_path.to_s))
        venv_dir = Pathname(env.fetch("LOGICA_VENV", config.root.join("tmp/logica_venv").to_s))

        raise LogicaError, "#{python} not found. Install Python 3 and try again." unless which.call(python)
        raise LogicaError, "requirements not found: #{requirements}" unless requirements.exist?

        FileUtils.mkdir_p(venv_dir.parent)
        shell.system!(python, "-m", "venv", venv_dir.to_s) unless venv_dir.exist?

        stamp = venv_dir.join(".requirements.sha256")
        req_sha = Digest::SHA256.hexdigest(requirements.read)

        return if stamp.exist? && stamp.read.strip == req_sha

        venv_python = venv_dir.join(Util.venv_bin_dir, "python").to_s
        shell.system!(venv_python, "-m", "pip", "install", "--upgrade", "pip")
        shell.system!(venv_python, "-m", "pip", "install", "-r", requirements.to_s)

        stamp.write(req_sha)
      end
    end
  end
end
