# frozen_string_literal: true

require_relative "logica_compiler/version"
require_relative "logica_compiler/errors"

require_relative "logica_compiler/config"
require_relative "logica_compiler/sql_safety"
require_relative "logica_compiler/manifest"
require_relative "logica_compiler/compiler"
require_relative "logica_compiler/registry"

require_relative "logica_compiler/railtie" if defined?(Rails)
require_relative "logica_compiler/active_record/runner" if defined?(ActiveRecord)
