# frozen_string_literal: true

source "https://rubygems.org"

# Specify your gem's dependencies in logica_compiler.gemspec
gemspec

gem "rake", "~> 13.0"
gem "minitest", "~> 5.16"
gem "rubocop", "~> 1.21"
gem "rubocop-rails-omakase", require: false

# Test/e2e deps (gem runtime stays Rails-free; these are only for tests)
gem "activerecord", ">= 8.1", "< 9.0"
gem "sqlite3", ">= 1.6", "< 3.0"
