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

  it "selects thread websocket transport for background runtime" do
    runtime = TestSupport::Voice::RuntimeDouble.new(kind: :background)
    driver = nil
    Riffer::Voice::Adapters::OpenAIRealtime.new(
      model: "gpt-realtime",
      runtime_executor: runtime,
      driver_factory: lambda { |**kwargs|
        driver = TestSupport::Voice::DriverDouble.new(**kwargs)
      }
    )

    thread_calls = []
    async_calls = []
    selected = nil
    thread_connect = ->(url:, headers:) do
      thread_calls << {url: url, headers: headers}
      :thread_transport
    end
    async_connect = ->(url:, headers:) do
      async_calls << {url: url, headers: headers}
      :async_transport
    end

    with_overridden_transport_connects(thread_connect: thread_connect, async_connect: async_connect) do
      selected = driver.transport_factory.call(url: "wss://example.test/openai", headers: {"Authorization" => "Bearer key"})
    end

    expect(selected).must_equal :thread_transport
    expect(thread_calls.length).must_equal 1
    expect(async_calls).must_equal []
    expect(driver.response_state_lock).must_be_instance_of Mutex
  end

  it "selects async websocket transport for async runtime" do
    runtime = Struct.new(:kind, :task).new(:async, Object.new)
    driver = nil
    Riffer::Voice::Adapters::OpenAIRealtime.new(
      model: "gpt-realtime",
      runtime_executor: runtime,
      driver_factory: lambda { |**kwargs|
        driver = TestSupport::Voice::DriverDouble.new(**kwargs)
      }
    )

    thread_calls = []
    async_calls = []
    selected = nil
    thread_connect = ->(url:, headers:) do
      thread_calls << {url: url, headers: headers}
      :thread_transport
    end
    async_connect = ->(url:, headers:) do
      async_calls << {url: url, headers: headers}
      :async_transport
    end

    with_overridden_transport_connects(thread_connect: thread_connect, async_connect: async_connect) do
      selected = driver.transport_factory.call(url: "wss://example.test/openai", headers: {"Authorization" => "Bearer key"})
    end

    expect(selected).must_equal :async_transport
    expect(async_calls.length).must_equal 1
    expect(thread_calls).must_equal []
    expect(driver.response_state_lock.is_a?(Mutex)).must_equal false
  end

  private

  def with_overridden_transport_connects(thread_connect:, async_connect:)
    thread_singleton = Riffer::Voice::Transports::ThreadWebsocket.singleton_class
    async_singleton = Riffer::Voice::Transports::AsyncWebsocket.singleton_class
    original_thread_connect = thread_singleton.instance_method(:connect)
    original_async_connect = async_singleton.instance_method(:connect)

    thread_singleton.send(:remove_method, :connect)
    async_singleton.send(:remove_method, :connect)
    thread_singleton.send(:define_method, :connect, thread_connect)
    async_singleton.send(:define_method, :connect, async_connect)

    yield
  ensure
    thread_singleton.send(:remove_method, :connect)
    async_singleton.send(:remove_method, :connect)
    thread_singleton.send(:define_method, :connect, original_thread_connect)
    async_singleton.send(:define_method, :connect, original_async_connect)
  end
end
