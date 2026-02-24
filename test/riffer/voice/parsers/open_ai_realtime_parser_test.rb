# frozen_string_literal: true

require "test_helper"

describe Riffer::Voice::Parsers::OpenAIRealtimeParser do
  let(:parser) { Riffer::Voice::Parsers::OpenAIRealtimeParser.new }

  it "parses audio delta" do
    events = parser.call({"type" => "response.output_audio.delta", "delta" => "BASE64_AUDIO"})

    expect(events.first).must_be_instance_of Riffer::Voice::Events::AudioChunk
    expect(events.first.payload).must_equal "BASE64_AUDIO"
    expect(events.first.mime_type).must_equal "audio/pcm;rate=24000"
  end

  it "keeps parse_content_part private" do
    expect(parser.class.private_instance_methods(false)).must_include :parse_content_part
    expect(parser.class.public_instance_methods(false)).wont_include :parse_content_part
  end

  it "parses response.audio.delta alias" do
    events = parser.call({"type" => "response.audio.delta", "delta" => "BASE64_AUDIO"})

    expect(events.first).must_be_instance_of Riffer::Voice::Events::AudioChunk
    expect(events.first.payload).must_equal "BASE64_AUDIO"
  end

  it "parses response.audio.done alias with audio payload" do
    events = parser.call({"type" => "response.audio.done", "audio" => "BASE64_AUDIO"})

    expect(events.first).must_be_instance_of Riffer::Voice::Events::AudioChunk
    expect(events.first.payload).must_equal "BASE64_AUDIO"
  end

  it "parses input transcript completed" do
    events = parser.call({"type" => "conversation.item.input_audio_transcription.completed", "transcript" => "hello"})

    expect(events.first).must_be_instance_of Riffer::Voice::Events::InputTranscript
    expect(events.first.is_final).must_equal true
  end

  it "parses output transcript done" do
    events = parser.call({"type" => "response.output_audio_transcript.done", "transcript" => "hi"})

    expect(events.first).must_be_instance_of Riffer::Voice::Events::OutputTranscript
    expect(events.first.is_final).must_equal true
  end

  it "parses tool call arguments" do
    events = parser.call(
      {
        "type" => "response.function_call_arguments.done",
        "call_id" => "call_1",
        "name" => "lookup",
        "arguments" => "{\"id\":1}"
      }
    )

    event = events.first
    expect(event).must_be_instance_of Riffer::Voice::Events::ToolCall
    expect(event.arguments).must_equal({"id" => 1})
    expect(event.arguments_hash).must_equal({"id" => 1})
  end

  it "normalizes invalid tool call argument payloads to empty hash" do
    events = nil
    _output, error_output = capture_io do
      events = parser.call(
        {
          "type" => "response.function_call_arguments.done",
          "call_id" => "call_1",
          "name" => "lookup",
          "arguments" => "not-json"
        }
      )
    end

    event = events.first
    expect(event).must_be_instance_of Riffer::Voice::Events::ToolCall
    expect(event.arguments).must_equal({})
    expect(error_output).must_include "normalized invalid tool arguments"
    expect(error_output).must_include "json parse failed"
  end

  it "normalizes non-object json tool call arguments to empty hash" do
    events = nil
    _output, error_output = capture_io do
      events = parser.call(
        {
          "type" => "response.function_call_arguments.done",
          "call_id" => "call_1",
          "name" => "lookup",
          "arguments" => "[1,2,3]"
        }
      )
    end

    event = events.first
    expect(event).must_be_instance_of Riffer::Voice::Events::ToolCall
    expect(event.arguments).must_equal({})
    expect(error_output).must_include "normalized invalid tool arguments"
    expect(error_output).must_include "expected JSON object"
  end

  it "ignores function_call output items to avoid duplicate tool call events" do
    events = parser.call(
      {
        "type" => "response.output_item.done",
        "item" => {
          "type" => "function_call",
          "id" => "item_1",
          "call_id" => "call_1",
          "name" => "lookup",
          "arguments" => "{\"id\":1}"
        }
      }
    )

    expect(events).must_equal []
  end

  it "parses audio content from response.output_item.done message content" do
    events = parser.call(
      {
        "type" => "response.output_item.done",
        "item" => {
          "type" => "message",
          "content" => [
            {
              "type" => "audio",
              "audio" => "BASE64_AUDIO",
              "transcript" => "Hello there"
            }
          ]
        }
      }
    )

    expect(events.map(&:class)).must_equal([
      Riffer::Voice::Events::AudioChunk,
      Riffer::Voice::Events::OutputTranscript
    ])
    expect(events.first.payload).must_equal "BASE64_AUDIO"
    expect(events.last.text).must_equal "Hello there"
    expect(events.last.is_final).must_equal true
  end

  it "marks output_item.added message transcripts as non-final" do
    events = parser.call(
      {
        "type" => "response.output_item.added",
        "item" => {
          "type" => "message",
          "content" => [
            {
              "type" => "text",
              "text" => "Working..."
            }
          ]
        }
      }
    )

    expect(events.map(&:class)).must_equal([Riffer::Voice::Events::OutputTranscript])
    expect(events.first.text).must_equal "Working..."
    expect(events.first.is_final).must_equal false
  end

  it "parses audio chunk from response.content_part.added" do
    events = parser.call(
      {
        "type" => "response.content_part.added",
        "part" => {
          "type" => "audio",
          "audio" => "BASE64_AUDIO"
        }
      }
    )

    expect(events.map(&:class)).must_equal([Riffer::Voice::Events::AudioChunk])
    expect(events.first.payload).must_equal "BASE64_AUDIO"
  end

  it "parses response done with usage and turn complete" do
    events = parser.call(
      {
        "type" => "response.done",
        "response" => {
          "id" => "resp_1",
          "usage" => {
            "input_tokens" => 5,
            "output_tokens" => 7
          }
        }
      }
    )

    expect(events.map(&:class)).must_equal([
      Riffer::Voice::Events::Usage,
      Riffer::Voice::Events::TurnComplete
    ])
  end

  it "emits error when response.done status is failed" do
    events = parser.call(
      {
        "type" => "response.done",
        "response" => {
          "id" => "resp_1",
          "status" => "failed",
          "status_details" => {
            "error" => {
              "code" => "server_error",
              "message" => "Model failed to generate output."
            }
          }
        }
      }
    )

    expect(events.map(&:class)).must_equal([
      Riffer::Voice::Events::Error,
      Riffer::Voice::Events::TurnComplete
    ])
    expect(events.first.code).must_equal "server_error"
    expect(events.first.message).must_equal "Model failed to generate output."
    expect(events.first.retriable).must_equal true
  end

  it "does not emit error when response.done status is cancelled" do
    events = parser.call(
      {
        "type" => "response.done",
        "response" => {
          "id" => "resp_1",
          "status" => "cancelled",
          "status_details" => {
            "type" => "client_cancelled"
          }
        }
      }
    )

    expect(events.map(&:class)).must_equal([Riffer::Voice::Events::TurnComplete])
  end

  it "parses error event" do
    events = parser.call({"type" => "error", "error" => {"code" => "server_error", "message" => "try again"}})

    expect(events.first).must_be_instance_of Riffer::Voice::Events::Error
    expect(events.first.retriable).must_equal true
  end

  it "parses interrupt events" do
    events = parser.call({"type" => "input_audio_buffer.speech_started"})

    expect(events.first).must_be_instance_of Riffer::Voice::Events::Interrupt
  end
end
