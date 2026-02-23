# frozen_string_literal: true

require "test_helper"
require "support/voice_driver_test_helpers"
require "base64"

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
    expect(transport.writes.first.dig("session", "type")).must_equal "realtime"
    expect(transport.writes.first.dig("session", "model")).must_equal "gpt-realtime"
    expect(transport.writes.first.dig("session", "output_modalities")).must_equal ["audio"]
    expect(transport.writes.first.dig("session", "input_audio_format")).must_be_nil
    expect(transport.writes.first.dig("session", "output_audio_format")).must_be_nil
    expect(transport.writes.first.dig("session", "audio", "input", "format", "type")).must_equal "audio/pcm"
    expect(transport.writes.first.dig("session", "audio", "input", "format", "rate")).must_equal 24_000
    expect(transport.writes.first.dig("session", "audio", "input", "turn_detection", "type")).must_equal "semantic_vad"
    expect(transport.writes.first.dig("session", "audio", "input", "turn_detection", "create_response")).must_equal true
    expect(transport.writes.first.dig("session", "audio", "input", "turn_detection", "interrupt_response")).must_equal false
    expect(transport.writes.first.dig("session", "audio", "output", "format", "type")).must_equal "audio/pcm"
    expect(transport.writes.first.dig("session", "audio", "output", "format", "rate")).must_equal 24_000
    expect(transport.writes.first.dig("session", "audio", "output", "voice")).must_equal "alloy"
  end

  it "strips unsupported strict flag from session tools" do
    transport = VoiceDriverTestHelpers::FakeTransport.new

    driver = Riffer::Voice::Drivers::OpenAIRealtime.new(
      api_key: "openai-key",
      model: "gpt-realtime",
      transport_factory: ->(url:, headers:) { transport },
      parser: VoiceDriverTestHelpers::StubParser.new,
      task_resolver: -> { async_task }
    )

    tool = {
      "type" => "function",
      "name" => "lookup_clinic",
      "description" => "Lookup clinic info",
      "parameters" => {
        "type" => "object",
        "properties" => {
          "id" => {
            "type" => "string",
            "pattern" => "\\A\\+\\d{1,15}\\z"
          }
        },
        "required" => ["id"]
      },
      "strict" => true
    }

    driver.connect(system_prompt: "You are helpful", tools: [tool])

    written_tool = transport.writes.first.dig("session", "tools", 0)
    expect(written_tool["name"]).must_equal "lookup_clinic"
    expect(written_tool.key?("strict")).must_equal false
    expect(written_tool.dig("parameters", "properties", "id", "pattern")).must_equal "^\\+\\d{1,15}$"
  end

  it "maps legacy top-level turn_detection config into audio.input.turn_detection" do
    transport = VoiceDriverTestHelpers::FakeTransport.new

    driver = Riffer::Voice::Drivers::OpenAIRealtime.new(
      api_key: "openai-key",
      model: "gpt-realtime",
      transport_factory: ->(url:, headers:) { transport },
      parser: VoiceDriverTestHelpers::StubParser.new,
      task_resolver: -> { async_task }
    )

    driver.connect(
      system_prompt: "You are helpful",
      config: {
        turn_detection: {
          type: "server_vad",
          create_response: false
        }
      }
    )

    expect(transport.writes.first.dig("session", "turn_detection")).must_be_nil
    expect(transport.writes.first.dig("session", "audio", "input", "turn_detection", "type")).must_equal "server_vad"
    expect(transport.writes.first.dig("session", "audio", "input", "turn_detection", "create_response")).must_equal false
  end

  it "deep merges nested audio config without dropping required defaults" do
    transport = VoiceDriverTestHelpers::FakeTransport.new

    driver = Riffer::Voice::Drivers::OpenAIRealtime.new(
      api_key: "openai-key",
      model: "gpt-realtime",
      transport_factory: ->(url:, headers:) { transport },
      parser: VoiceDriverTestHelpers::StubParser.new,
      task_resolver: -> { async_task }
    )

    driver.connect(
      system_prompt: "You are helpful",
      config: {
        audio: {
          output: {
            voice: "verse"
          }
        }
      }
    )

    expect(transport.writes.first.dig("session", "audio", "output", "voice")).must_equal "verse"
    expect(transport.writes.first.dig("session", "audio", "output", "format", "type")).must_equal "audio/pcm"
    expect(transport.writes.first.dig("session", "audio", "output", "format", "rate")).must_equal 24_000
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
    expect(transport.writes[1].key?("mime_type")).must_equal false
    expect(transport.writes[2].dig("item", "content", 0, "text")).must_equal "hello"
    expect(transport.writes[3]["type"]).must_equal "response.create"
    expect(transport.writes[3].dig("response", "output_modalities")).must_equal ["audio"]
    expect(transport.writes[3].dig("response", "audio", "output", "voice")).must_equal "alloy"
    expect(transport.writes[3].dig("response", "audio", "output", "format", "type")).must_equal "audio/pcm"
    expect(transport.writes[3].dig("response", "audio", "output", "format", "rate")).must_equal 24_000
    expect(transport.writes[4].dig("item", "call_id")).must_equal "call_1"
  end

  it "defers response.create until response is completed when one is already active" do
    transport = VoiceDriverTestHelpers::FakeTransport.new(
      frames: [
        {"type" => "response.done", "response" => {"status" => "completed"}}.to_json
      ]
    )

    driver = Riffer::Voice::Drivers::OpenAIRealtime.new(
      api_key: "openai-key",
      model: "gpt-realtime",
      transport_factory: ->(url:, headers:) { transport },
      parser: VoiceDriverTestHelpers::StubParser.new,
      task_resolver: -> { async_task }
    )

    driver.connect(system_prompt: "You are helpful")
    driver.send_text_turn(text: "hello", role: "user")
    driver.send_tool_response(call_id: "call_1", result: {ok: true})

    expect(transport.writes.map { |payload| payload["type"] }).must_equal(
      [
        "session.update",
        "conversation.item.create",
        "response.create",
        "conversation.item.create"
      ]
    )

    async_task.children.first.run

    expect(transport.writes.last["type"]).must_equal "response.create"
  end

  it "clears response.create tracking when provider returns non-active-response error" do
    transport = VoiceDriverTestHelpers::FakeTransport.new

    driver = Riffer::Voice::Drivers::OpenAIRealtime.new(
      api_key: "openai-key",
      model: "gpt-realtime",
      transport_factory: ->(url:, headers:) { transport },
      parser: VoiceDriverTestHelpers::StubParser.new,
      task_resolver: -> { async_task }
    )

    driver.connect(system_prompt: "You are helpful")
    driver.send_text_turn(text: "hello", role: "user")
    driver.send(
      :update_response_tracking,
      {"type" => "error", "error" => {"code" => "rate_limit_exceeded", "message" => "rate limited"}}
    )

    driver.send_tool_response(call_id: "call_1", result: {ok: true})

    expect(transport.writes.map { |payload| payload["type"] }).must_equal(
      [
        "session.update",
        "conversation.item.create",
        "response.create",
        "conversation.item.create",
        "response.create"
      ]
    )
  end

  it "upsamples 16k PCM audio chunks to 24k for OpenAI realtime input" do
    transport = VoiceDriverTestHelpers::FakeTransport.new

    driver = Riffer::Voice::Drivers::OpenAIRealtime.new(
      api_key: "openai-key",
      model: "gpt-realtime",
      transport_factory: ->(url:, headers:) { transport },
      parser: VoiceDriverTestHelpers::StubParser.new,
      task_resolver: -> { async_task }
    )

    driver.connect(system_prompt: "You are helpful")

    source_pcm = [100, -100, 200, -200].pack("s<*")
    source_payload = Base64.strict_encode64(source_pcm)
    driver.send_audio_chunk(payload: source_payload, mime_type: "audio/pcm;rate=16000")

    sent_payload = transport.writes[1]["audio"]
    sent_pcm = Base64.strict_decode64(sent_payload)
    expect(sent_pcm.unpack("s<*").length).must_be :>, source_pcm.unpack("s<*").length
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
