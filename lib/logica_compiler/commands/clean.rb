# frozen_string_literal: true

require "fileutils"

require_relative "base"

module LogicaCompiler
  module Commands
    class Clean < Base
      def call(config_path:, logica_bin_override: nil)
        config = load_config(config_path:, logica_bin_override:)
        dir = config.output_dir_path
        FileUtils.mkdir_p(dir)

        Dir.glob(dir.join("*").to_s).each do |path|
          next if File.basename(path) == ".keep"

          FileUtils.rm_rf(path)
        end

        true
      end
    end
  end
end
