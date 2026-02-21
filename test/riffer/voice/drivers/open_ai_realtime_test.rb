# frozen_string_literal: true

require "test_helper"
require "support/voice_driver_test_helpers"

describe Riffer::Voice::Drivers::OpenAIRealtime do
  let(:async_task) { VoiceDriverTestHelpers::FakeAsyncTask.new }

  it "connects with authorization header and writes session.update" do
    transport = VoiceDriverTestHelpers::FakeTransport.new
    connection_args = {}

    driver = Riffer::Voice::Drivers::OpenAIRealtime.new(
      api_key: "openai-key",
      model: "gpt-realtime",
      transport_factory: lambda do |url:, headers:|
        connection_args[:url] = url
        connection_args[:headers] = headers
        transport
      end,
      parser: VoiceDriverTestHelpers::StubParser.new,
      task_resolver: -> { async_task }
    )

    connected = driver.connect(system_prompt: "You are helpful")

    expect(connected).must_equal true
    expect(connection_args[:url]).must_include "model=gpt-realtime"
    expect(connection_args[:headers]["Authorization"]).must_equal "Bearer openai-key"
    expect(transport.writes.first["type"]).must_equal "session.update"
  end

  it "emits parser events from the reader loop" do
    transport = VoiceDriverTestHelpers::FakeTransport.new(frames: [{"ok" => true}.to_json])
    events = []

    driver = Riffer::Voice::Drivers::OpenAIRealtime.new(
      api_key: "openai-key",
      model: "gpt-realtime",
      transport_factory: ->(url:, headers:) { transport },
      parser: VoiceDriverTestHelpers::StubParser.new(events: [Riffer::Voice::Events::AudioChunk.new(payload: "AUDIO", mime_type: "audio/pcm")]),
      task_resolver: -> { async_task }
    )

    driver.connect(system_prompt: "You are helpful", callbacks: {on_event: ->(event) { events << event }})
    async_task.children.first.run

    expect(events.first).must_be_instance_of Riffer::Voice::Events::AudioChunk
  end

  it "sends audio text and tool response payloads" do
    transport = VoiceDriverTestHelpers::FakeTransport.new

    driver = Riffer::Voice::Drivers::OpenAIRealtime.new(
      api_key: "openai-key",
      model: "gpt-realtime",
      transport_factory: ->(url:, headers:) { transport },
      parser: VoiceDriverTestHelpers::StubParser.new,
      task_resolver: -> { async_task }
    )

    driver.connect(system_prompt: "You are helpful")
    driver.send_audio_chunk(payload: "AUDIO", mime_type: "audio/pcm")
    driver.send_text_turn(text: "hello", role: "user")
    driver.send_tool_response(call_id: "call_1", result: {ok: true})

    expect(transport.writes.size).must_equal 5
    expect(transport.writes[1]["type"]).must_equal "input_audio_buffer.append"
    expect(transport.writes[2].dig("item", "content", 0, "text")).must_equal "hello"
    expect(transport.writes[3].dig("item", "call_id")).must_equal "call_1"
    expect(transport.writes[4]["type"]).must_equal "response.create"
  end

  it "raises when no async task context is available" do
    driver = Riffer::Voice::Drivers::OpenAIRealtime.new(
      api_key: "openai-key",
      model: "gpt-realtime",
      transport_factory: ->(url:, headers:) { VoiceDriverTestHelpers::FakeTransport.new },
      parser: VoiceDriverTestHelpers::StubParser.new,
      task_resolver: -> {}
    )

    expect {
      driver.connect(system_prompt: "You are helpful")
    }.must_raise Riffer::ArgumentError
  end

  it "closes idempotently" do
    transport = VoiceDriverTestHelpers::FakeTransport.new

    driver = Riffer::Voice::Drivers::OpenAIRealtime.new(
      api_key: "openai-key",
      model: "gpt-realtime",
      transport_factory: ->(url:, headers:) { transport },
      parser: VoiceDriverTestHelpers::StubParser.new,
      task_resolver: -> { async_task }
    )

    driver.connect(system_prompt: "You are helpful")
    driver.close(reason: "done")
    driver.close(reason: "done_again")

    expect(driver).wont_be :connected?
    expect(transport).must_be :closed?
  end
end
