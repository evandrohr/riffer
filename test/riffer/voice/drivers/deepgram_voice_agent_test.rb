# frozen_string_literal: true

require "test_helper"
require "support/voice_driver_test_helpers"
require "base64"

describe Riffer::Voice::Drivers::DeepgramVoiceAgent do
  let(:async_task) { VoiceDriverTestHelpers::FakeAsyncTask.new }

  it "connects with authorization header and writes Settings payload" do
    transport = VoiceDriverTestHelpers::FakeTransport.new
    connection_args = {}

    driver = Riffer::Voice::Drivers::DeepgramVoiceAgent.new(
      api_key: "deepgram-key",
      model: TestSupport::VoiceModels::DEEPGRAM_MODEL,
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
    expect(connection_args[:url]).must_equal Riffer::Voice::Drivers::DeepgramVoiceAgent::DEFAULT_ENDPOINT
    expect(connection_args[:headers]["Authorization"]).must_equal "token deepgram-key"

    settings = transport.writes.first
    expect(settings["type"]).must_equal "Settings"
    expect(settings.dig("agent", "think", "provider", "type")).must_equal "open_ai"
    expect(settings.dig("agent", "think", "provider", "model")).must_equal TestSupport::VoiceModels::DEEPGRAM_MODEL
    expect(settings.dig("agent", "think", "prompt")).must_equal "You are helpful"
  end

  it "normalizes tool definitions into think.functions" do
    transport = VoiceDriverTestHelpers::FakeTransport.new

    tool = {
      "type" => "function",
      "function" => {
        "name" => "lookup_patient",
        "description" => "Lookup patient",
        "parameters" => {
          "type" => "object",
          "properties" => {
            "phone" => {"type" => "string"}
          },
          "required" => ["phone"]
        }
      }
    }

    driver = Riffer::Voice::Drivers::DeepgramVoiceAgent.new(
      api_key: "deepgram-key",
      model: TestSupport::VoiceModels::DEEPGRAM_MODEL,
      transport_factory: ->(url:, headers:) { transport },
      parser: VoiceDriverTestHelpers::StubParser.new,
      task_resolver: -> { async_task }
    )

    driver.connect(system_prompt: "You are helpful", tools: [tool])

    function_payload = transport.writes.first.dig("agent", "think", "functions", 0)
    expect(function_payload).must_equal(
      {
        "name" => "lookup_patient",
        "description" => "Lookup patient",
        "parameters" => {
          "type" => "object",
          "properties" => {
            "phone" => {"type" => "string"}
          },
          "required" => ["phone"]
        }
      }
    )
  end

  it "emits parser events from json frames" do
    transport = VoiceDriverTestHelpers::FakeTransport.new(frames: [{"type" => "ConversationText"}.to_json])
    events = []

    driver = Riffer::Voice::Drivers::DeepgramVoiceAgent.new(
      api_key: "deepgram-key",
      model: TestSupport::VoiceModels::DEEPGRAM_MODEL,
      transport_factory: ->(url:, headers:) { transport },
      parser: VoiceDriverTestHelpers::StubParser.new(events: [Riffer::Voice::Events::TurnComplete.new]),
      task_resolver: -> { async_task }
    )

    driver.connect(system_prompt: "You are helpful", callbacks: {on_event: ->(event) { events << event }})
    async_task.children.first.run

    expect(events.map(&:class)).must_equal([Riffer::Voice::Events::TurnComplete])
  end

  it "emits audio chunk events from binary frames" do
    binary_frame = "\x01\x02\x03".b
    transport = VoiceDriverTestHelpers::FakeTransport.new(frames: [binary_frame])
    events = []

    driver = Riffer::Voice::Drivers::DeepgramVoiceAgent.new(
      api_key: "deepgram-key",
      model: TestSupport::VoiceModels::DEEPGRAM_MODEL,
      transport_factory: ->(url:, headers:) { transport },
      parser: VoiceDriverTestHelpers::StubParser.new,
      task_resolver: -> { async_task }
    )

    driver.connect(system_prompt: "You are helpful", callbacks: {on_event: ->(event) { events << event }})
    async_task.children.first.run

    expect(events.map(&:class)).must_equal([Riffer::Voice::Events::AudioChunk])
    expect(events.first.payload).must_equal(Base64.strict_encode64(binary_frame))
    expect(events.first.mime_type).must_equal("audio/pcm;rate=24000")
  end

  it "sends audio text and tool response payloads" do
    transport = VoiceDriverTestHelpers::FakeTransport.new

    driver = Riffer::Voice::Drivers::DeepgramVoiceAgent.new(
      api_key: "deepgram-key",
      model: TestSupport::VoiceModels::DEEPGRAM_MODEL,
      transport_factory: ->(url:, headers:) { transport },
      parser: VoiceDriverTestHelpers::StubParser.new,
      task_resolver: -> { async_task }
    )

    driver.connect(system_prompt: "You are helpful")
    driver.send_audio_chunk(payload: Base64.strict_encode64("AUDIO"), mime_type: "audio/pcm;rate=16000")
    driver.send_text_turn(text: "hello")
    driver.send_tool_response(call_id: "call_1", result: {ok: true})

    expect(transport.binary_writes).must_equal(["AUDIO"])
    expect(transport.writes[1]).must_equal(
      {
        "type" => "InjectUserMessage",
        "content" => "hello"
      }
    )
    expect(transport.writes[2]).must_equal(
      {
        "type" => "FunctionCallResponse",
        "id" => "call_1",
        "content" => "{\"ok\":true}"
      }
    )
  end

  it "includes function name in tool response when provided by wrapper payload" do
    transport = VoiceDriverTestHelpers::FakeTransport.new

    driver = Riffer::Voice::Drivers::DeepgramVoiceAgent.new(
      api_key: "deepgram-key",
      model: TestSupport::VoiceModels::DEEPGRAM_MODEL,
      transport_factory: ->(url:, headers:) { transport },
      parser: VoiceDriverTestHelpers::StubParser.new,
      task_resolver: -> { async_task }
    )

    driver.connect(system_prompt: "You are helpful")
    driver.send_tool_response(
      call_id: "call_named",
      result: {
        "name" => "get_time",
        "response" => {"time" => "10:00 AM"}
      }
    )

    expect(transport.writes[1]).must_equal(
      {
        "type" => "FunctionCallResponse",
        "id" => "call_named",
        "name" => "get_time",
        "content" => "{\"time\":\"10:00 AM\"}"
      }
    )
  end

  it "sends tool responses immediately even when the agent is speaking" do
    transport = VoiceDriverTestHelpers::FakeTransport.new

    driver = Riffer::Voice::Drivers::DeepgramVoiceAgent.new(
      api_key: "deepgram-key",
      model: TestSupport::VoiceModels::DEEPGRAM_MODEL,
      transport_factory: ->(url:, headers:) { transport },
      parser: VoiceDriverTestHelpers::StubParser.new,
      task_resolver: -> { async_task }
    )

    driver.connect(system_prompt: "You are helpful")
    driver.instance_variable_set(:@agent_speaking, true)

    driver.send_tool_response(call_id: "call_queued", result: {ok: true})

    expect(transport.writes[1]).must_equal(
      {
        "type" => "FunctionCallResponse",
        "id" => "call_queued",
        "content" => "{\"ok\":true}"
      }
    )
    expect(driver.instance_variable_get(:@pending_tool_responses)).must_equal([])
  end

  it "requeues rejected tool responses after injection_refused due to speaking" do
    transport = VoiceDriverTestHelpers::FakeTransport.new

    driver = Riffer::Voice::Drivers::DeepgramVoiceAgent.new(
      api_key: "deepgram-key",
      model: TestSupport::VoiceModels::DEEPGRAM_MODEL,
      transport_factory: ->(url:, headers:) { transport },
      parser: VoiceDriverTestHelpers::StubParser.new,
      task_resolver: -> { async_task }
    )

    driver.connect(system_prompt: "You are helpful")
    driver.send_tool_response(call_id: "call_retry", result: {ok: true})

    driver.send(
      :handle_server_payload,
      {
        "type" => "InjectionRefused",
        "message" => "Cannot inject message while agent is currently speaking"
      }
    )

    expect(driver.instance_variable_get(:@pending_tool_responses).length).must_equal(1)

    driver.send(
      :handle_server_payload,
      {
        "type" => "AgentAudioDone"
      }
    )

    retries = transport.writes.select { |message| message["id"] == "call_retry" }
    expect(retries.length).must_equal(2)
  end

  it "flushes queued tool responses once any non-speaking payload arrives" do
    transport = VoiceDriverTestHelpers::FakeTransport.new

    driver = Riffer::Voice::Drivers::DeepgramVoiceAgent.new(
      api_key: "deepgram-key",
      model: TestSupport::VoiceModels::DEEPGRAM_MODEL,
      transport_factory: ->(url:, headers:) { transport },
      parser: VoiceDriverTestHelpers::StubParser.new,
      task_resolver: -> { async_task }
    )

    driver.connect(system_prompt: "You are helpful")
    driver.send_tool_response(call_id: "call_flush", result: {ok: true})
    driver.instance_variable_set(:@pending_tool_responses, [transport.writes.last])
    driver.instance_variable_set(:@agent_speaking, false)

    driver.send(:handle_server_payload, {"type" => "ConversationText", "role" => "assistant", "content" => "ok"})

    flushes = transport.writes.select { |message| message["id"] == "call_flush" }
    expect(flushes.length).must_equal(2)
  end

  it "raises from send_audio_chunk when payload is invalid base64 and emits error" do
    transport = VoiceDriverTestHelpers::FakeTransport.new
    errors = []

    driver = Riffer::Voice::Drivers::DeepgramVoiceAgent.new(
      api_key: "deepgram-key",
      model: TestSupport::VoiceModels::DEEPGRAM_MODEL,
      transport_factory: ->(url:, headers:) { transport },
      parser: VoiceDriverTestHelpers::StubParser.new,
      task_resolver: -> { async_task }
    )

    driver.connect(
      system_prompt: "You are helpful",
      callbacks: {on_error: ->(event) { errors << event }}
    )

    error = expect {
      driver.send_audio_chunk(payload: "not-base64", mime_type: "audio/pcm")
    }.must_raise Riffer::Error

    expect(error.message).must_include("failed sending audio chunk")
    expect(errors.map(&:code)).must_include("deepgram_voice_agent_send_audio_failed")
  end

  it "raises when no async task context is available" do
    driver = Riffer::Voice::Drivers::DeepgramVoiceAgent.new(
      api_key: "deepgram-key",
      model: TestSupport::VoiceModels::DEEPGRAM_MODEL,
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

    driver = Riffer::Voice::Drivers::DeepgramVoiceAgent.new(
      api_key: "deepgram-key",
      model: TestSupport::VoiceModels::DEEPGRAM_MODEL,
      transport_factory: ->(url:, headers:) { transport },
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
