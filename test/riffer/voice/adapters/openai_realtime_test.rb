# frozen_string_literal: true

require "test_helper"
require_relative "../../../support/voice/fake_adapter"

describe Riffer::Voice::Adapters::OpenAIRealtime do
  it "bridges runtime scheduling through task_resolver and delegates operations" do
    runtime = TestSupport::Voice::RuntimeDouble.new
    driver = nil
    adapter = Riffer::Voice::Adapters::OpenAIRealtime.new(
      model: "gpt-realtime",
      runtime_executor: runtime,
      driver_factory: lambda { |**kwargs|
        driver = TestSupport::Voice::DriverDouble.new(**kwargs)
      }
    )

    callback_events = []
    connect_result = adapter.connect(
      system_prompt: "You are helpful",
      tools: [],
      config: {temperature: 0.2},
      on_event: ->(event) { callback_events << event }
    )

    expect(connect_result).must_equal true
    expect(driver.model).must_equal "gpt-realtime"
    expect(driver.connect_calls.length).must_equal 1

    ran = false
    driver.task_resolver.call.async { ran = true }
    expect(ran).must_equal true
    expect(runtime.scheduled_blocks.length).must_equal 1

    adapter.send_text_turn(text: "hello")
    adapter.send_audio_chunk(payload: "BASE64", mime_type: "audio/pcm")
    adapter.send_tool_response(call_id: "call_1", result: {ok: true})

    expect(driver.text_turns).must_equal ["hello"]
    expect(driver.audio_chunks).must_equal([{payload: "BASE64", mime_type: "audio/pcm"}])
    expect(driver.tool_responses).must_equal([{call_id: "call_1", result: {ok: true}}])

    event = Riffer::Voice::Events::TurnComplete.new
    driver.emit(event)
    expect(callback_events).must_equal [event]

    adapter.close
    expect(driver.closed).must_equal true
  end
end
