# frozen_string_literal: true

require "test_helper"

describe Riffer::Voice::Runtime::ManagedAsync do
  it "delegates scheduling through async task when supported" do
    task = Class.new do
      attr_reader :annotations

      def initialize
        @annotations = []
      end

      def async(annotation:, &block)
        @annotations << annotation
        block.call
        :child_task
      end
    end.new

    runtime = Riffer::Voice::Runtime::ManagedAsync.new(task: task)
    result = runtime.schedule { :ok }

    expect(result).must_equal :child_task
    expect(task.annotations).must_equal ["riffer-voice-runtime"]
    expect(runtime.kind).must_equal :async
    expect(runtime.background?).must_equal false
    expect(runtime.closed?).must_equal false
  end

  it "falls back to inline execution when task lacks async" do
    runtime = Riffer::Voice::Runtime::ManagedAsync.new(task: Object.new)
    result = nil
    _output, error_output = capture_io do
      result = runtime.schedule { :ok }
    end

    expect(result).must_equal :ok
    expect(error_output).must_include "managed async runtime task does not implement :async"
  end

  it "requires a block for schedule" do
    runtime = Riffer::Voice::Runtime::ManagedAsync.new(task: Object.new)

    expect {
      runtime.schedule
    }.must_raise Riffer::ArgumentError
  end
end
