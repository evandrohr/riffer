# frozen_string_literal: true

module TestSupport
  module Voice
    class RuntimeDouble
      attr_reader :kind
      attr_reader :scheduled_blocks

      def initialize(kind: :background)
        @kind = kind
        @scheduled_blocks = []
      end

      def schedule(&block)
        @scheduled_blocks << block
        block.call
        true
      end
    end

    class DriverDouble
      attr_reader :model, :task_resolver, :transport_factory, :response_state_lock, :logger, :connect_calls, :text_turns, :audio_chunks, :tool_responses, :closed

      def initialize(model:, task_resolver:, logger:, transport_factory: nil, response_state_lock: nil)
        @model = model
        @task_resolver = task_resolver
        @transport_factory = transport_factory
        @response_state_lock = response_state_lock
        @logger = logger
        @connect_calls = []
        @text_turns = []
        @audio_chunks = []
        @tool_responses = []
        @closed = false
        @on_event = nil
      end

      def connect(system_prompt:, tools:, config:, callbacks:)
        @connect_calls << {
          system_prompt: system_prompt,
          tools: tools,
          config: config
        }
        @on_event = callbacks[:on_event]
        true
      end

      def send_text_turn(text:)
        @text_turns << text
      end

      def send_audio_chunk(payload:, mime_type:)
        @audio_chunks << {
          payload: payload,
          mime_type: mime_type
        }
      end

      def send_tool_response(call_id:, result:)
        @tool_responses << {
          call_id: call_id,
          result: result
        }
      end

      def close
        @closed = true
      end

      def emit(event)
        @on_event&.call(event)
      end
    end

    class FakeAdapter
      attr_reader :connect_calls, :text_turns, :audio_chunks, :tool_responses

      def initialize(connect_result: true)
        @connect_result = connect_result
        @connect_calls = []
        @text_turns = []
        @audio_chunks = []
        @tool_responses = []
        @on_event = nil
        @connected = false
        @closed = false
      end

      def connect(system_prompt:, tools:, config:, on_event:)
        @connect_calls << {
          system_prompt: system_prompt,
          tools: tools,
          config: config
        }
        @on_event = on_event
        @connected = @connect_result == true
        @connect_result
      end

      def connected?
        @connected == true
      end

      def send_text_turn(text:)
        @text_turns << text
      end

      def send_audio_chunk(payload:, mime_type:)
        @audio_chunks << {
          payload: payload,
          mime_type: mime_type
        }
      end

      def send_tool_response(call_id:, result:)
        @tool_responses << {
          call_id: call_id,
          result: result
        }
      end

      def emit(event)
        @on_event&.call(event)
      end

      def close
        @connected = false
        @closed = true
      end

      def disconnect!
        @connected = false
      end

      def closed?
        @closed == true
      end
    end
  end
end
