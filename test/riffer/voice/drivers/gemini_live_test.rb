# frozen_string_literal: true

require "test_helper"
require "support/voice_driver_test_helpers"

describe Riffer::Voice::Drivers::GeminiLive do
  let(:async_task) { VoiceDriverTestHelpers::FakeAsyncTask.new }
  let(:transport) { VoiceDriverTestHelpers::FakeTransport.new }
  let(:transport_factory) { ->(url:, headers:) { transport } }

  it "connects and writes setup payload" do
    driver = Riffer::Voice::Drivers::GeminiLive.new(
      api_key: "test-key",
      model: "gemini-2.5-flash-native-audio-preview-12-2025",
      transport_factory: transport_factory,
      parser: VoiceDriverTestHelpers::StubParser.new,
      task_resolver: -> { async_task }
    )

    connected = driver.connect(system_prompt: "You are helpful")

    expect(connected).must_equal true
    expect(driver).must_be :connected?
    expect(transport.writes.first.dig("setup", "model")).must_equal "models/gemini-2.5-flash-native-audio-preview-12-2025"
    expect(transport.writes.first.dig("setup", "generationConfig", "responseModalities")).must_equal ["AUDIO"]
    expect(async_task.children.size).must_equal 1
  end

  it "does not duplicate models prefix when model is already prefixed" do
    driver = Riffer::Voice::Drivers::GeminiLive.new(
      api_key: "test-key",
      model: "models/gemini-2.5-flash-native-audio-preview-12-2025",
      transport_factory: transport_factory,
      parser: VoiceDriverTestHelpers::StubParser.new,
      task_resolver: -> { async_task }
    )

    driver.connect(system_prompt: "You are helpful")

    expect(transport.writes.first.dig("setup", "model")).must_equal "models/gemini-2.5-flash-native-audio-preview-12-2025"
  end

  it "emits parser events from the reader loop" do
    events = []
    parser = VoiceDriverTestHelpers::StubParser.new(events: [Riffer::Voice::Events::TurnComplete.new])
    transport_with_frame = VoiceDriverTestHelpers::FakeTransport.new(frames: [{"ok" => true}.to_json])

    driver = Riffer::Voice::Drivers::GeminiLive.new(
      api_key: "test-key",
      model: "gemini-2.5-flash-native-audio-preview-12-2025",
      transport_factory: ->(url:, headers:) { transport_with_frame },
      parser: parser,
      task_resolver: -> { async_task }
    )

    driver.connect(system_prompt: "You are helpful", callbacks: {on_event: ->(event) { events << event }})
    async_task.children.first.run

    expect(events.size).must_equal 1
    expect(events.first).must_be_instance_of Riffer::Voice::Events::TurnComplete
  end

  it "sends audio text and tool response payloads" do
    driver = Riffer::Voice::Drivers::GeminiLive.new(
      api_key: "test-key",
      model: "gemini-2.5-flash-native-audio-preview-12-2025",
      transport_factory: transport_factory,
      parser: VoiceDriverTestHelpers::StubParser.new,
      task_resolver: -> { async_task }
    )

    driver.connect(system_prompt: "You are helpful")
    driver.send_audio_chunk(payload: "AUDIO", mime_type: "audio/pcm;rate=16000")
    driver.send_text_turn(text: "hello", role: "user")
    driver.send_tool_response(call_id: "call_1", result: {response: {ok: true}})

    expect(transport.writes.size).must_equal 4
    expect(transport.writes[1]).must_equal(
      "realtimeInput" => {
        "audio" => {
          "data" => "AUDIO",
          "mimeType" => "audio/pcm;rate=16000"
        }
      }
    )
    expect(transport.writes[2].dig("clientContent", "turns", 0, "parts", 0, "text")).must_equal "hello"
    expect(transport.writes[3].dig("toolResponse", "functionResponses", 0, "id")).must_equal "call_1"
  end

  it "merges provided config over defaults" do
    driver = Riffer::Voice::Drivers::GeminiLive.new(
      api_key: "test-key",
      model: "gemini-2.5-flash-native-audio-preview-12-2025",
      transport_factory: transport_factory,
      parser: VoiceDriverTestHelpers::StubParser.new,
      task_resolver: -> { async_task }
    )

    driver.connect(
      system_prompt: "You are helpful",
      config: {
        generationConfig: {
          responseModalities: ["TEXT"],
          temperature: 0.2
        }
      }
    )

    expect(transport.writes.first.dig("setup", "generationConfig", "responseModalities")).must_equal ["TEXT"]
    expect(transport.writes.first.dig("setup", "generationConfig", "temperature")).must_equal 0.2
  end

  it "removes unsupported schema keys from tool definitions" do
    custom_tool = {
      functionDeclarations: [
        {
          name: "find_patient",
          description: "Find patient",
          parameters: {
            type: "object",
            properties: {
              phone: {
                type: "string",
                additionalProperties: false
              }
            },
            required: ["phone"],
            additionalProperties: false
          }
        }
      ]
    }

    driver = Riffer::Voice::Drivers::GeminiLive.new(
      api_key: "test-key",
      model: "gemini-2.5-flash-native-audio-preview-12-2025",
      transport_factory: transport_factory,
      parser: VoiceDriverTestHelpers::StubParser.new,
      task_resolver: -> { async_task }
    )

    driver.connect(system_prompt: "You are helpful", tools: [custom_tool])

    parameters = transport.writes.first.dig("setup", "tools", 0, "functionDeclarations", 0, "parameters")
    expect(parameters.key?("additionalProperties")).must_equal false
    expect(parameters.dig("properties", "phone", "additionalProperties")).must_be_nil
  end

  it "emits callback_error when callback raises" do
    errors = []
    parser = VoiceDriverTestHelpers::StubParser.new(events: [Riffer::Voice::Events::TurnComplete.new])
    transport_with_frame = VoiceDriverTestHelpers::FakeTransport.new(frames: [{"ok" => true}.to_json])

    driver = Riffer::Voice::Drivers::GeminiLive.new(
      api_key: "test-key",
      model: "gemini-2.5-flash-native-audio-preview-12-2025",
      transport_factory: ->(url:, headers:) { transport_with_frame },
      parser: parser,
      task_resolver: -> { async_task }
    )

    driver.connect(
      system_prompt: "You are helpful",
      callbacks: {
        on_event: ->(_event) { raise "boom" },
        on_error: ->(event) { errors << event }
      }
    )

    async_task.children.first.run

    expect(errors.map(&:code)).must_include "callback_error"
  end

  it "raises when no async task context is available" do
    driver = Riffer::Voice::Drivers::GeminiLive.new(
      api_key: "test-key",
      model: "gemini-2.5-flash-native-audio-preview-12-2025",
      transport_factory: transport_factory,
      parser: VoiceDriverTestHelpers::StubParser.new,
      task_resolver: -> {}
    )

    expect {
      driver.connect(system_prompt: "You are helpful")
    }.must_raise Riffer::ArgumentError
  end

  it "closes idempotently" do
    driver = Riffer::Voice::Drivers::GeminiLive.new(
      api_key: "test-key",
      model: "gemini-2.5-flash-native-audio-preview-12-2025",
      transport_factory: transport_factory,
      parser: VoiceDriverTestHelpers::StubParser.new,
      task_resolver: -> { async_task }
    )

    driver.connect(system_prompt: "You are helpful")
    driver.close(reason: "done")
    driver.close(reason: "again")

    expect(driver).wont_be :connected?
    expect(transport).must_be :closed?
  end
end
