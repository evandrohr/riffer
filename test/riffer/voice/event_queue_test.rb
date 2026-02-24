# frozen_string_literal: true

require "test_helper"

describe Riffer::Voice::EventQueue do
  let(:queue) { Riffer::Voice::EventQueue.new }

  it "pushes and pops events in FIFO order" do
    first = Riffer::Voice::Events::OutputTranscript.new(text: "a")
    second = Riffer::Voice::Events::TurnComplete.new

    expect(queue.push(first)).must_equal true
    expect(queue.push(second)).must_equal true

    expect(queue.pop(timeout: 0)).must_equal first
    expect(queue.pop(timeout: 0)).must_equal second
    expect(queue.pop(timeout: 0)).must_be_nil
  end

  it "returns nil when timeout expires without events" do
    start = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    result = queue.pop(timeout: 0.05)
    elapsed = Process.clock_gettime(Process::CLOCK_MONOTONIC) - start

    expect(result).must_be_nil
    expect(elapsed).must_be :>=, 0.04
  end

  it "returns nil after queue is closed and empty" do
    expect(queue.close).must_equal true
    expect(queue.closed?).must_equal true
    expect(queue.pop(timeout: 0)).must_be_nil
  end

  it "rejects pushes after close" do
    queue.close

    event = Riffer::Voice::Events::TurnComplete.new
    expect(queue.push(event)).must_equal false
  end

  it "supports fiber mode timeout without blocking on condition variables" do
    fiber_queue = Riffer::Voice::EventQueue.new(mode: :fiber, fiber_poll_interval: 0.001)

    start = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    result = fiber_queue.pop(timeout: 0.01)
    elapsed = Process.clock_gettime(Process::CLOCK_MONOTONIC) - start

    expect(result).must_be_nil
    expect(elapsed).must_be :>=, 0.009
  end

  it "supports fiber mode push and pop" do
    fiber_queue = Riffer::Voice::EventQueue.new(mode: :fiber, fiber_poll_interval: 0.001)
    event = Riffer::Voice::Events::OutputTranscript.new(text: "fiber")

    expect(fiber_queue.push(event)).must_equal true
    expect(fiber_queue.pop(timeout: 0)).must_equal event
  end

  it "validates fiber_poll_interval is greater than zero" do
    expect {
      Riffer::Voice::EventQueue.new(mode: :fiber, fiber_poll_interval: 0)
    }.must_raise Riffer::ArgumentError

    expect {
      Riffer::Voice::EventQueue.new(mode: :fiber, fiber_poll_interval: -0.01)
    }.must_raise Riffer::ArgumentError
  end
end
