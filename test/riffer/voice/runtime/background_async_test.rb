# frozen_string_literal: true

require "test_helper"

describe Riffer::Voice::Runtime::BackgroundAsync do
  it "executes scheduled blocks on background worker" do
    runtime = Riffer::Voice::Runtime::BackgroundAsync.new
    result_queue = Queue.new

    runtime.schedule { result_queue << :ok }

    deadline = Time.now + 1
    sleep 0.01 until !result_queue.empty? || Time.now >= deadline

    expect(result_queue.pop).must_equal :ok
    runtime.shutdown
  end

  it "is idempotent on shutdown" do
    runtime = Riffer::Voice::Runtime::BackgroundAsync.new

    expect(runtime.shutdown).must_equal true
    expect(runtime.shutdown).must_equal true
    expect(runtime).must_be :closed?
  end

  it "rejects schedule after shutdown" do
    runtime = Riffer::Voice::Runtime::BackgroundAsync.new
    runtime.shutdown

    expect {
      runtime.schedule { :nope }
    }.must_raise Riffer::Error
  end
end
