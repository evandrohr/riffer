# frozen_string_literal: true

require "test_helper"
require_relative "../../support/voice/fake_adapter"

describe "Riffer::Voice::Session event APIs" do
  let(:adapter) { TestSupport::Voice::FakeAdapter.new }
  let(:session) do
    Riffer::Voice.connect(
      model: "openai/gpt-realtime",
      system_prompt: "You are helpful",
      runtime: :background,
      adapter_factory: ->(**_kwargs) { adapter }
    )
  end

  after do
    session.close unless session.closed?
  end

  it "returns pushed events via next_event" do
    session
    event = Riffer::Voice::Events::OutputTranscript.new(text: "hello")
    adapter.emit(event)

    received = session.next_event(timeout: 0)
    expect(received).must_equal event
  end

  it "returns nil from next_event when no event arrives before timeout" do
    expect(session.next_event(timeout: 0.01)).must_be_nil
  end

  it "yields queued events in order via events enumerator and stops after close" do
    session
    first = Riffer::Voice::Events::OutputTranscript.new(text: "a")
    second = Riffer::Voice::Events::TurnComplete.new
    adapter.emit(first)
    adapter.emit(second)

    received = []
    consumer = Thread.new do
      session.events.each do |event|
        received << event
        break if received.size == 2
      end
    end

    consumer.join
    session.close

    expect(received).must_equal [first, second]
  end

  it "validates emitted event type" do
    expect {
      session.send(:emit_event, "not_an_event")
    }.must_raise Riffer::ArgumentError
  end

  it "uses fiber queue behavior for async runtime kind" do
    runtime_executor = Struct.new(:kind) do
      def shutdown
        true
      end
    end.new(:async)

    fiber_adapter = TestSupport::Voice::FakeAdapter.new
    fiber_session = Riffer::Voice::Session.new(
      model: "openai/gpt-realtime",
      system_prompt: "You are helpful",
      tools: [],
      config: {},
      runtime: :async,
      runtime_executor: runtime_executor,
      adapter: fiber_adapter
    )

    event = Riffer::Voice::Events::TurnComplete.new
    fiber_adapter.emit(event)

    expect(fiber_session.next_event(timeout: 0)).must_equal event
    fiber_session.close
  end
end
