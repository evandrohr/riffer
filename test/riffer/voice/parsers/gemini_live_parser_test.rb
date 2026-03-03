# frozen_string_literal: true

require "test_helper"

describe Riffer::Voice::Parsers::GeminiLiveParser do
  let(:parser) { Riffer::Voice::Parsers::GeminiLiveParser.new }

  it "parses audio, transcript, tool call, interrupt, turn complete and usage" do
    payload = {
      "serverContent" => {
        "modelTurn" => {
          "parts" => [
            {
              "inlineData" => {
                "data" => "BASE64_AUDIO",
                "mimeType" => "audio/pcm;rate=24000"
              }
            },
            {
              "inlineData" => {
                "data" => "BASE64_AUDIO_2",
                "mimeType" => "audio/pcm;rate=24000"
              }
            }
          ]
        },
        "inputTranscription" => {
          "text" => "hello",
          "isFinal" => true
        },
        "outputTranscription" => {
          "text" => "hi there",
          "isFinal" => false
        },
        "interrupted" => true,
        "turnComplete" => true
      },
      "toolCall" => {
        "functionCalls" => [
          {
            "id" => "call_123",
            "name" => "lookup_patient",
            "args" => {"phone" => "111"}
          }
        ]
      },
      "usageMetadata" => {
        "promptTokenCount" => 11,
        "candidatesTokenCount" => 12,
        "inputAudioTokenCount" => 13,
        "outputAudioTokenCount" => 14
      }
    }

    events = parser.call(payload)

    expect(events.map(&:class)).must_equal [
      Riffer::Voice::Events::AudioChunk,
      Riffer::Voice::Events::AudioChunk,
      Riffer::Voice::Events::InputTranscript,
      Riffer::Voice::Events::OutputTranscript,
      Riffer::Voice::Events::ToolCall,
      Riffer::Voice::Events::Interrupt,
      Riffer::Voice::Events::TurnComplete,
      Riffer::Voice::Events::Usage
    ]
    expect(events[0].payload).must_equal "BASE64_AUDIO"
    expect(events[1].payload).must_equal "BASE64_AUDIO_2"
  end

  it "returns empty array for unsupported payload" do
    expect(parser.call({"foo" => "bar"})).must_equal []
  end

  it "parses transcripts when text is emitted via parts" do
    payload = {
      "serverContent" => {
        "inputTranscription" => {
          "parts" => [
            {"text" => "Need an appointment"},
            {"text" => "next week"}
          ],
          "isFinal" => true
        },
        "outputTranscription" => {
          "parts" => [
            {"text" => "Sure"},
            {"text" => "I can help with that"}
          ],
          "isFinal" => false
        }
      }
    }

    events = parser.call(payload)

    expect(events.map(&:class)).must_equal [
      Riffer::Voice::Events::InputTranscript,
      Riffer::Voice::Events::OutputTranscript
    ]
    expect(events[0].text).must_equal "Need an appointment\nnext week"
    expect(events[0].is_final).must_equal true
    expect(events[1].text).must_equal "Sure\nI can help with that"
    expect(events[1].is_final).must_equal false
  end

  it "normalizes string tool call args into hash" do
    payload = {
      "toolCall" => {
        "functionCalls" => [
          {
            "id" => "call_123",
            "name" => "lookup_patient",
            "args" => "{\"phone\":\"111\"}"
          }
        ]
      }
    }

    events = parser.call(payload)
    expect(events.map(&:class)).must_equal([Riffer::Voice::Events::ToolCall])
    expect(events.first.arguments).must_equal({"phone" => "111"})
  end

  it "normalizes invalid string tool call args to empty hash" do
    payload = {
      "toolCall" => {
        "functionCalls" => [
          {
            "id" => "call_123",
            "name" => "lookup_patient",
            "args" => "not-json"
          }
        ]
      }
    }

    events = nil
    _output, error_output = capture_io do
      events = parser.call(payload)
    end
    expect(events.map(&:class)).must_equal([Riffer::Voice::Events::ToolCall])
    expect(events.first.arguments).must_equal({})
    expect(error_output).must_include "normalized invalid tool arguments"
    expect(error_output).must_include "json parse failed"
  end

  it "treats modelTurn text-only frames as non-audio-only" do
    data = {}
    server_content = {
      "modelTurn" => {
        "parts" => [
          {"text" => "hello"}
        ]
      }
    }

    expect(parser.send(:audio_only_frame?, data, server_content)).must_equal false
  end
end
