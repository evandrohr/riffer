# frozen_string_literal: true

require "test_helper"

describe Riffer::Voice::Runtime::Resolver do
  it "resolves :auto to background runtime when async task is absent" do
    runtime = Riffer::Voice::Runtime::Resolver.resolve(
      requested_mode: :auto,
      task_resolver: -> {}
    )

    expect(runtime).must_be_instance_of Riffer::Voice::Runtime::BackgroundAsync
    runtime.shutdown
  end

  it "resolves :auto to managed async runtime when async task exists" do
    fake_task = Object.new
    runtime = Riffer::Voice::Runtime::Resolver.resolve(
      requested_mode: :auto,
      task_resolver: -> { fake_task }
    )

    expect(runtime).must_be_instance_of Riffer::Voice::Runtime::ManagedAsync
    expect(runtime.task).must_equal fake_task
  end

  it "resolves :background to background runtime" do
    runtime = Riffer::Voice::Runtime::Resolver.resolve(
      requested_mode: :background,
      task_resolver: -> {}
    )

    expect(runtime).must_be_instance_of Riffer::Voice::Runtime::BackgroundAsync
    runtime.shutdown
  end

  it "resolves :async when async task exists" do
    fake_task = Object.new
    runtime = Riffer::Voice::Runtime::Resolver.resolve(
      requested_mode: :async,
      task_resolver: -> { fake_task }
    )

    expect(runtime).must_be_instance_of Riffer::Voice::Runtime::ManagedAsync
    expect(runtime.task).must_equal fake_task
  end

  it "raises when :async runtime is requested without async task" do
    expect {
      Riffer::Voice::Runtime::Resolver.resolve(
        requested_mode: :async,
        task_resolver: -> {}
      )
    }.must_raise Riffer::ArgumentError
  end
end
