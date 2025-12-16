# frozen_string_literal: true

require "test_helper"
require "pathname"

require "logica_compiler/watcher"

class WatcherTest < Minitest::Test
  CaptureLogger =
    Struct.new(:infos, :warns) do
      def initialize = super([], [])
      def info(message) = infos << message && true
      def warn(message) = warns << message && true
    end

  class CaptureSleeper
    attr_reader :slept

    def initialize
      @slept = false
    end

    def sleep(_duration = nil)
      @slept = true
      nil
    end
  end

  class FakeListener
    attr_reader :root, :opts, :block, :started

    def initialize(root, opts, &block)
      @root = root
      @opts = opts
      @block = block
      @started = false
    end

    def start
      @started = true
    end
  end

  def test_start_raises_in_production
    sleeper = CaptureSleeper.new
    watcher =
      LogicaCompiler::Watcher.new(
        production_check: -> { true },
        config_loader: ->(_path) { flunk("should not load config in production") },
        sleeper:
      )

    error = assert_raises(LogicaCompiler::Error) { watcher.start! }
    assert_match(/development only/, error.message)
    refute sleeper.slept
  end

  def test_start_sets_up_listener_and_sleeps
    logger = CaptureLogger.new
    sleeper = CaptureSleeper.new

    config = Struct.new(:root).new(Pathname("/tmp/app"))

    compiler = Minitest::Mock.new
    compiler.expect(:compile_all!, true)

    listener = nil
    listener_factory = lambda do |root, **opts, &block|
      listener = FakeListener.new(root, opts, &block)
    end

    watcher =
      LogicaCompiler::Watcher.new(
        config_loader: ->(_path) { config },
        compiler_factory: ->(_config) { compiler },
        listener_factory: listener_factory,
        logger:,
        sleeper:,
        production_check: -> { false }
      )

    watcher.start!

    assert listener
    assert listener.started
    assert_equal config.root.join("logica/programs").to_s, listener.root
    assert_equal(/\.l\z/, listener.opts.fetch(:only))
    assert_equal 1.0, listener.opts.fetch(:wait_for_delay)
    assert sleeper.slept
    assert logger.infos.any? { _1.include?("[logica] watching") }

    listener.block.call(["a.l"], [], [])
    compiler.verify
    assert logger.infos.any? { _1.include?("change detected") }
    assert logger.infos.any? { _1.include?("compile done") }
  end

  def test_listener_callback_logs_warning_when_compile_fails
    logger = CaptureLogger.new
    sleeper = CaptureSleeper.new

    config = Struct.new(:root).new(Pathname("/tmp/app"))

    compiler = Object.new
    def compiler.compile_all! = raise("boom")

    listener = nil
    listener_factory = lambda do |root, **opts, &block|
      listener = FakeListener.new(root, opts, &block)
    end

    watcher =
      LogicaCompiler::Watcher.new(
        config_loader: ->(_path) { config },
        compiler_factory: ->(_config) { compiler },
        listener_factory: listener_factory,
        logger:,
        sleeper:,
        production_check: -> { false }
      )

    watcher.start!
    listener.block.call([], [], [])

    assert logger.warns.any? { _1.include?("compile failed") }
    assert logger.warns.any? { _1.include?("boom") }
  end
end
