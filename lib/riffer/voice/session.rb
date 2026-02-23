# frozen_string_literal: true
# rbs_inline: enabled

# Public voice session API.
#
# Provides lifecycle, input contracts, and event stream/poll APIs.
# Provider transport wiring is delegated to internal adapters.
class Riffer::Voice::Session
  # Voice model in provider/model format.
  attr_reader :model #: String

  # System prompt used for session setup.
  attr_reader :system_prompt #: String

  # Tool classes available to the session.
  attr_reader :tools #: Array[singleton(Riffer::Tool)]

  # Provider/runtime config payload.
  attr_reader :config #: Hash[Symbol | String, untyped]

  # Runtime selection (:auto, :async, :background).
  attr_reader :runtime #: Symbol

  #: (model: String, system_prompt: String, tools: Array[singleton(Riffer::Tool)], config: Hash[Symbol | String, untyped], runtime: Symbol, runtime_executor: (Riffer::Voice::Runtime::ManagedAsync | Riffer::Voice::Runtime::BackgroundAsync), adapter: untyped) -> void
  def initialize(model:, system_prompt:, tools:, config:, runtime:, runtime_executor:, adapter:)
    @model = model
    @system_prompt = system_prompt
    @tools = tools
    @config = config
    @runtime = runtime
    @runtime_executor = runtime_executor
    @adapter = adapter
    @event_queue = Riffer::Voice::EventQueue.new(mode: queue_mode_for(runtime_executor))
    @connected = false
    @closed = false
    connect_adapter!
  end

  #: () -> Symbol
  def runtime_kind
    @runtime_executor.kind
  end

  #: () -> bool
  def connected?
    @connected == true
  end

  #: () -> bool
  def closed?
    @closed == true
  end

  #: (text: String) -> bool
  def send_text_turn(text:)
    ensure_open!
    raise Riffer::ArgumentError, "text must be a non-empty String" unless text.is_a?(String) && !text.empty?

    @adapter.send_text_turn(text: text)
    true
  end

  #: (payload: String, mime_type: String) -> bool
  def send_audio_chunk(payload:, mime_type:)
    ensure_open!
    raise Riffer::ArgumentError, "payload must be a non-empty String" unless payload.is_a?(String) && !payload.empty?
    raise Riffer::ArgumentError, "mime_type must be a non-empty String" unless mime_type.is_a?(String) && !mime_type.empty?

    @adapter.send_audio_chunk(payload: payload, mime_type: mime_type)
    true
  end

  #: (call_id: String, result: untyped) -> bool
  def send_tool_response(call_id:, result:)
    ensure_open!
    raise Riffer::ArgumentError, "call_id must be a non-empty String" unless call_id.is_a?(String) && !call_id.empty?
    raise Riffer::ArgumentError, "result must not be nil" if result.nil?

    @adapter.send_tool_response(call_id: call_id, result: result)
    true
  end

  #: () -> Enumerator[Riffer::Voice::Events::Base, void]
  def events
    ensure_open!
    Enumerator.new do |yielder|
      loop do
        event = @event_queue.pop(timeout: nil)
        break if event.nil?

        yielder << event
      end
    end
  end

  #: (?timeout: Numeric?) -> Riffer::Voice::Events::Base?
  def next_event(timeout: nil)
    ensure_open!
    invalid_timeout = !timeout.nil? && (!timeout.is_a?(Numeric) || timeout < 0)
    raise Riffer::ArgumentError, "timeout must be nil or >= 0" if invalid_timeout

    @event_queue.pop(timeout: timeout)
  end

  #: () -> void
  def close
    return if closed?

    @event_queue.close
    begin
      @adapter.close
    ensure
      @runtime_executor.shutdown
      @closed = true
      @connected = false
    end
  end

  private

  #: () -> void
  def connect_adapter!
    required_methods = [:connect, :send_text_turn, :send_audio_chunk, :send_tool_response, :close]
    missing_methods = required_methods.reject { |method_name| @adapter.respond_to?(method_name) }
    unless missing_methods.empty?
      raise Riffer::ArgumentError, "adapter must respond to: #{required_methods.join(", ")}"
    end

    connected = @adapter.connect(
      system_prompt: @system_prompt,
      tools: @tools,
      config: @config,
      on_event: method(:emit_event)
    )
    raise Riffer::Error, "Voice adapter failed to connect" unless connected

    @connected = true
  rescue
    @event_queue.close
    begin
      @adapter.close if @adapter.respond_to?(:close)
    rescue
      nil
    end
    @runtime_executor.shutdown
    @closed = true
    @connected = false
    raise
  end

  #: ((Riffer::Voice::Runtime::ManagedAsync | Riffer::Voice::Runtime::BackgroundAsync)) -> Symbol
  def queue_mode_for(runtime_executor)
    if runtime_executor.kind == :async
      :fiber
    else
      :thread
    end
  end

  #: (Riffer::Voice::Events::Base) -> Riffer::Voice::Events::Base
  def emit_event(event)
    raise Riffer::ArgumentError, "event must be a voice event" unless event.is_a?(Riffer::Voice::Events::Base)

    @event_queue.push(event)
    event
  end

  #: () -> void
  def ensure_open!
    raise Riffer::Error, "Voice session is closed" if closed?
    raise Riffer::Error, "Voice session is not connected" unless connected?
  end
end
