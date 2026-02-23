# frozen_string_literal: true

require "test_helper"

describe Riffer::Voice::Session do
  describe ".connect" do
    it "returns a connected session with provided attributes" do
      session = Riffer::Voice.connect(
        model: "openai/gpt-realtime",
        system_prompt: "You are helpful",
        tools: [],
        config: {temperature: 0.2},
        runtime: :auto
      )

      expect(session).must_be_instance_of Riffer::Voice::Session
      expect(session.model).must_equal "openai/gpt-realtime"
      expect(session.system_prompt).must_equal "You are helpful"
      expect(session.config).must_equal({temperature: 0.2})
      expect(session.runtime).must_equal :auto
      expect([:async, :background]).must_include session.runtime_kind
      expect(session).must_be :connected?
      expect(session).wont_be :closed?
      session.close
    end

    it "supports explicit background runtime mode" do
      session = Riffer::Voice.connect(
        model: "openai/gpt-realtime",
        system_prompt: "You are helpful",
        runtime: :background
      )

      expect(session.runtime).must_equal :background
      expect(session.runtime_kind).must_equal :background
      session.close
    end

    it "requires async context for :async runtime mode" do
      expect {
        Riffer::Voice.connect(
          model: "openai/gpt-realtime",
          system_prompt: "You are helpful",
          runtime: :async
        )
      }.must_raise Riffer::ArgumentError
    end

    it "validates model and system_prompt" do
      expect {
        Riffer::Voice.connect(model: "", system_prompt: "ok")
      }.must_raise Riffer::ArgumentError

      expect {
        Riffer::Voice.connect(model: "openai/gpt-realtime", system_prompt: "")
      }.must_raise Riffer::ArgumentError
    end

    it "validates tools and config types" do
      expect {
        Riffer::Voice.connect(model: "openai/gpt-realtime", system_prompt: "ok", tools: :bad)
      }.must_raise Riffer::ArgumentError

      expect {
        Riffer::Voice.connect(model: "openai/gpt-realtime", system_prompt: "ok", config: [])
      }.must_raise Riffer::ArgumentError
    end

    it "validates runtime option" do
      expect {
        Riffer::Voice.connect(model: "openai/gpt-realtime", system_prompt: "ok", runtime: :unknown)
      }.must_raise Riffer::ArgumentError
    end
  end

  describe "lifecycle and input contracts" do
    let(:session) { Riffer::Voice.connect(model: "openai/gpt-realtime", system_prompt: "You are helpful") }

    it "accepts valid send calls while open" do
      expect(session.send_text_turn(text: "hello")).must_equal true
      expect(session.send_audio_chunk(payload: "BASE64", mime_type: "audio/pcm")).must_equal true
      expect(session.send_tool_response(call_id: "call_1", result: {ok: true})).must_equal true
    end

    it "returns no events from skeleton next_event API" do
      expect(session.next_event).must_be_nil
      expect(session.next_event(timeout: 0)).must_be_nil
    end

    it "returns an enumerator from events" do
      events = session.events

      expect(events).must_be_instance_of Enumerator
      expect(events.take(1)).must_equal []
    end

    it "raises on invalid send input" do
      expect { session.send_text_turn(text: "") }.must_raise Riffer::ArgumentError
      expect { session.send_audio_chunk(payload: "", mime_type: "audio/pcm") }.must_raise Riffer::ArgumentError
      expect { session.send_audio_chunk(payload: "BASE64", mime_type: "") }.must_raise Riffer::ArgumentError
      expect { session.send_tool_response(call_id: "", result: {ok: true}) }.must_raise Riffer::ArgumentError
    end

    it "validates next_event timeout" do
      expect { session.next_event(timeout: -1) }.must_raise Riffer::ArgumentError
    end

    it "closes idempotently and blocks further operations" do
      session.close
      session.close

      expect(session).wont_be :connected?
      expect(session).must_be :closed?

      expect { session.send_text_turn(text: "hi") }.must_raise Riffer::Error
      expect { session.send_audio_chunk(payload: "BASE64", mime_type: "audio/pcm") }.must_raise Riffer::Error
      expect { session.send_tool_response(call_id: "call_1", result: {}) }.must_raise Riffer::Error
      expect { session.events }.must_raise Riffer::Error
      expect { session.next_event }.must_raise Riffer::Error
    end
  end
end
