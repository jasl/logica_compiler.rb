# frozen_string_literal: true

module LogicaCompiler
  module Deps
    class Env
      MISSING = :__missing__

      def [](key) = ENV[key]
      def fetch(key, *args, &block) = ENV.fetch(key, *args, &block)
      def key?(key) = ENV.key?(key)

      def set(key, value)
        ENV[key] = value
      end

      def delete(key)
        ENV.delete(key)
      end

      def with_temp(updates)
        previous = {}
        updates.each do |k, v|
          previous[k] = key?(k) ? ENV[k] : MISSING
          v.nil? ? delete(k) : set(k, v)
        end

        yield
      ensure
        previous.each do |k, v|
          v == MISSING ? delete(k) : set(k, v)
        end
      end
    end
  end
end
