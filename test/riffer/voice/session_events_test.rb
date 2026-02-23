# frozen_string_literal: true

require "test_helper"

describe "Riffer::Voice::Session event APIs" do
  let(:session) do
    Riffer::Voice.connect(
      model: "openai/gpt-realtime",
      system_prompt: "You are helpful",
      runtime: :background
    )
  end

  after do
    session.close unless session.closed?
  end

  it "returns pushed events via next_event" do
    event = Riffer::Voice::Events::OutputTranscript.new(text: "hello")
    session.send(:emit_event, event)

    received = session.next_event(timeout: 0)
    expect(received).must_equal event
  end

  it "returns nil from next_event when no event arrives before timeout" do
    expect(session.next_event(timeout: 0.01)).must_be_nil
  end

  it "yields queued events in order via events enumerator and stops after close" do
    first = Riffer::Voice::Events::OutputTranscript.new(text: "a")
    second = Riffer::Voice::Events::TurnComplete.new
    session.send(:emit_event, first)
    session.send(:emit_event, second)

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

    fiber_session = Riffer::Voice::Session.new(
      model: "openai/gpt-realtime",
      system_prompt: "You are helpful",
      tools: [],
      config: {},
      runtime: :async,
      runtime_executor: runtime_executor
    )

    event = Riffer::Voice::Events::TurnComplete.new
    fiber_session.send(:emit_event, event)

    expect(fiber_session.next_event(timeout: 0)).must_equal event
    fiber_session.close
  end
end
