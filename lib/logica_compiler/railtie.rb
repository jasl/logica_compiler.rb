# frozen_string_literal: true

require "rails/railtie"

module LogicaCompiler
  class Railtie < ::Rails::Railtie
    rake_tasks do
      load File.expand_path("tasks/logica_compiler.rake", __dir__)
    end
  end
end
