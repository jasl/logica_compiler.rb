# frozen_string_literal: true

require_relative "lib/logica_compiler/version"

Gem::Specification.new do |spec|
  spec.name = "logica_compiler"
  spec.version = LogicaCompiler::VERSION
  spec.authors = ["jasl"]
  spec.email = ["jasl9187@hotmail.com"]

  spec.summary = "Compile Logica programs to digested SQL + manifest."
  spec.description = "A small compiler wrapper around Logica (Python) that precompiles .l programs into digested SQL files + manifest, with optional ActiveRecord runner."
  spec.homepage = "https://github.com/jasl/vibe_tavern"
  spec.license = "MIT"
  spec.required_ruby_version = ">= 3.2.0"

  spec.metadata["homepage_uri"] = spec.homepage
  spec.metadata["source_code_uri"] = "#{spec.homepage}/tree/main/vendor/logica_compiler"

  # Specify which files should be added to the gem when it is released.
  # The `git ls-files -z` loads the files in the RubyGem that have been added into git.
  gemspec = File.basename(__FILE__)
  spec.files = IO.popen(%w[git ls-files -z], chdir: __dir__, err: IO::NULL) do |ls|
    ls.readlines("\x0", chomp: true).reject do |f|
      (f == gemspec) ||
        f.start_with?(*%w[bin/ Gemfile .gitignore test/ .github/ .rubocop.yml])
    end
  end
  spec.bindir = "exe"
  spec.executables = spec.files.grep(%r{\Aexe/}) { |f| File.basename(f) }
  spec.require_paths = ["lib"]

  spec.add_dependency "listen", ">= 3.8", "< 4.0"
  spec.add_dependency "thor", ">= 1.3", "< 2.0"

  spec.add_development_dependency "activerecord", ">= 8.1", "< 9.0"
  spec.add_development_dependency "minitest", "~> 5.16"
  spec.add_development_dependency "sqlite3", ">= 1.6", "< 3.0"

  # For more information and examples about making a new gem, check out our
  # guide at: https://bundler.io/guides/creating_gem.html
end
