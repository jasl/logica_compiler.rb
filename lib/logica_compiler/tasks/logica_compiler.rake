# frozen_string_literal: true

namespace :logica_compiler do
  desc "Install LogicaCompiler integration into the current Rails app"
  task install: :environment do
    require "pathname"
    require "logica_compiler/installer"

    root =
      if defined?(Rails) && Rails.respond_to?(:root)
        Pathname(Rails.root)
      else
        Pathname(Dir.pwd)
      end

    force = ENV["FORCE"] == "1"

    LogicaCompiler::Installer.new(root:, force:).run!
  end
end
