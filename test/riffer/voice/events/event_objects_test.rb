# frozen_string_literal: true

require "test_helper"

describe "Riffer::Voice::Events" do
  it "serializes AudioChunk" do
    event = Riffer::Voice::Events::AudioChunk.new(payload: "abc", mime_type: "audio/pcm")

    expect(event.to_h).must_equal(
      role: :assistant,
      payload: "abc",
      mime_type: "audio/pcm"
    )
  end

  it "serializes InputTranscript" do
    event = Riffer::Voice::Events::InputTranscript.new(text: "hello", is_final: true, metadata: {source: "vad"})

    expect(event.to_h).must_equal(
      role: :user,
      text: "hello",
      is_final: true,
      metadata: {source: "vad"}
    )
  end

  it "serializes OutputTranscript" do
    event = Riffer::Voice::Events::OutputTranscript.new(text: "hi", is_final: false, metadata: {provider: "x"})

    expect(event.to_h).must_equal(
      role: :assistant,
      text: "hi",
      is_final: false,
      metadata: {provider: "x"}
    )
  end

  it "serializes ToolCall" do
    event = Riffer::Voice::Events::ToolCall.new(call_id: "call_1", item_id: "item_1", name: "lookup", arguments: {id: 1})

    expect(event.to_h).must_equal(
      role: :assistant,
      call_id: "call_1",
      item_id: "item_1",
      name: "lookup",
      arguments: {"id" => 1}
    )
  end

  it "exposes arguments_hash as a hash with string keys" do
    event = Riffer::Voice::Events::ToolCall.new(call_id: "call_1", name: "lookup", arguments: {id: 1})

    expect(event.arguments_hash).must_equal({"id" => 1})
  end

  it "requires tool call arguments to be a hash" do
    expect {
      Riffer::Voice::Events::ToolCall.new(call_id: "call_1", name: "lookup", arguments: "{\"id\":1}")
    }.must_raise Riffer::ArgumentError
  end

  it "serializes Interrupt" do
    event = Riffer::Voice::Events::Interrupt.new(reason: "speech_started")

    expect(event.to_h).must_equal(role: :system, reason: "speech_started")
  end

  it "serializes TurnComplete" do
    event = Riffer::Voice::Events::TurnComplete.new(metadata: {response_id: "res_1"})

    expect(event.to_h).must_equal(role: :assistant, metadata: {response_id: "res_1"})
  end

  it "serializes Usage" do
    event = Riffer::Voice::Events::Usage.new(
      input_tokens: 10,
      output_tokens: 20,
      input_audio_tokens: 30,
      output_audio_tokens: 40,
      metadata: {provider: "openai"}
    )

    expect(event.to_h).must_equal(
      role: :assistant,
      input_tokens: 10,
      output_tokens: 20,
      input_audio_tokens: 30,
      output_audio_tokens: 40,
      metadata: {provider: "openai"}
    )
  end

  it "serializes Error" do
    event = Riffer::Voice::Events::Error.new(code: "provider_error", message: "bad request", retriable: false, metadata: {status: 400})

    expect(event.to_h).must_equal(
      role: :system,
      code: "provider_error",
      message: "bad request",
      retriable: false,
      metadata: {status: 400}
    )
  end
end
