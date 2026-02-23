# frozen_string_literal: true

require "test_helper"
require_relative "../../support/voice/fake_adapter"

describe Riffer::Voice::Session do
  describe ".connect" do
    let(:created_adapters) { [] }
    let(:adapter_factory) do
      lambda do |adapter_identifier:, model:, runtime_executor:|
        adapter = TestSupport::Voice::FakeAdapter.new
        created_adapters << {
          adapter: adapter,
          adapter_identifier: adapter_identifier,
          model: model,
          runtime_executor: runtime_executor
        }
        adapter
      end
    end

    it "returns a connected session with provided attributes" do
      session = Riffer::Voice.connect(
        model: "openai/gpt-realtime",
        system_prompt: "You are helpful",
        tools: [],
        config: {temperature: 0.2},
        runtime: :auto,
        adapter_factory: adapter_factory
      )

      expect(session).must_be_instance_of Riffer::Voice::Session
      expect(session.model).must_equal "openai/gpt-realtime"
      expect(session.system_prompt).must_equal "You are helpful"
      expect(session.config).must_equal({temperature: 0.2})
      expect(session.runtime).must_equal :auto
      expect([:async, :background]).must_include session.runtime_kind
      expect(session).must_be :connected?
      expect(session).wont_be :closed?
      expect(created_adapters.length).must_equal 1
      expect(created_adapters.first[:adapter_identifier]).must_equal :openai_realtime
      expect(created_adapters.first[:model]).must_equal "gpt-realtime"
      session.close
    end

    it "supports explicit background runtime mode" do
      session = Riffer::Voice.connect(
        model: "openai/gpt-realtime",
        system_prompt: "You are helpful",
        runtime: :background,
        adapter_factory: adapter_factory
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
        Riffer::Voice.connect(model: "", system_prompt: "ok", adapter_factory: adapter_factory)
      }.must_raise Riffer::ArgumentError

      expect {
        Riffer::Voice.connect(model: "openai/gpt-realtime", system_prompt: "", adapter_factory: adapter_factory)
      }.must_raise Riffer::ArgumentError
    end

    it "validates tools and config types" do
      expect {
        Riffer::Voice.connect(model: "openai/gpt-realtime", system_prompt: "ok", tools: :bad, adapter_factory: adapter_factory)
      }.must_raise Riffer::ArgumentError

      expect {
        Riffer::Voice.connect(model: "openai/gpt-realtime", system_prompt: "ok", config: [], adapter_factory: adapter_factory)
      }.must_raise Riffer::ArgumentError
    end

    it "validates runtime option" do
      expect {
        Riffer::Voice.connect(model: "openai/gpt-realtime", system_prompt: "ok", runtime: :unknown, adapter_factory: adapter_factory)
      }.must_raise Riffer::ArgumentError
    end

    it "validates provider prefix in model identifier" do
      expect {
        Riffer::Voice.connect(model: "gpt-realtime", system_prompt: "ok", adapter_factory: adapter_factory)
      }.must_raise Riffer::ArgumentError
    end

    it "validates adapter_factory contract" do
      expect {
        Riffer::Voice.connect(model: "openai/gpt-realtime", system_prompt: "ok", adapter_factory: 123)
      }.must_raise Riffer::ArgumentError
    end
  end

  describe "lifecycle and input contracts" do
    let(:adapter) { TestSupport::Voice::FakeAdapter.new }
    let(:session) do
      Riffer::Voice.connect(
        model: "openai/gpt-realtime",
        system_prompt: "You are helpful",
        adapter_factory: ->(**_kwargs) { adapter }
      )
    end

    after do
      session.close unless session.closed?
    end

    it "accepts valid send calls while open" do
      expect(session.send_text_turn(text: "hello")).must_equal true
      expect(session.send_audio_chunk(payload: "BASE64", mime_type: "audio/pcm")).must_equal true
      expect(session.send_tool_response(call_id: "call_1", result: {ok: true})).must_equal true

      expect(adapter.text_turns).must_equal ["hello"]
      expect(adapter.audio_chunks).must_equal([{payload: "BASE64", mime_type: "audio/pcm"}])
      expect(adapter.tool_responses).must_equal([{call_id: "call_1", result: {ok: true}}])
    end

    it "does not send nil tool response payloads" do
      expect(session.send_tool_response(call_id: "call_1", result: nil)).must_equal false
      expect(adapter.tool_responses).must_equal []
    end

    it "returns nil when no event arrives before timeout" do
      expect(session.next_event(timeout: 0.01)).must_be_nil
      expect(session.next_event(timeout: 0)).must_be_nil
    end

    it "returns an enumerator from events" do
      events = session.events

      expect(events).must_be_instance_of Enumerator
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
      expect(adapter).must_be :closed?

      expect { session.send_text_turn(text: "hi") }.must_raise Riffer::Error
      expect { session.send_audio_chunk(payload: "BASE64", mime_type: "audio/pcm") }.must_raise Riffer::Error
      expect { session.send_tool_response(call_id: "call_1", result: {}) }.must_raise Riffer::Error
      expect { session.events }.must_raise Riffer::Error
      expect { session.next_event }.must_raise Riffer::Error
    end
  end
end
