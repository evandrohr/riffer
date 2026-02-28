# frozen_string_literal: true
# rbs_inline: enabled

# High-level orchestration wrapper for realtime voice sessions.
#
# Riffer::Voice::Agent keeps Riffer::Voice::Session as a low-level transport API
# and adds optional automatic tool-call execution using Riffer::Tool classes.
#
#   class SupportVoiceAgent < Riffer::Voice::Agent
#     model "openai/gpt-realtime-1.5"
#     instructions "You are a concise support assistant."
#     uses_tools [LookupAccountTool]
#   end
#
#   agent = SupportVoiceAgent.connect(runtime: :auto)
#   agent.send_text_turn(text: "Hello")
#   agent.events.each do |event|
#     puts event.class.name
#   end
#
class Riffer::Voice::Agent
  extend Riffer::Helpers::Validations
  extend Riffer::Voice::Agent::ClassConfiguration

  include Riffer::Voice::Agent::Utilities
  include Riffer::Voice::Agent::Callbacks
  include Riffer::Voice::Agent::Policy
  include Riffer::Voice::Agent::ToolExecution
  include Riffer::Voice::Agent::Resolution
  include Riffer::Voice::Agent::SessionLifecycle
  include Riffer::Voice::Agent::StateSnapshot
  include Riffer::Voice::Agent::EventLoop

  # Connected voice session.
  attr_reader :session #: Riffer::Voice::Session?

  # Tool execution context passed to Riffer::Tool#call.
  attr_accessor :tool_context #: Hash[Symbol, untyped]?

  CALLBACK_KEYS = [
    :on_event,
    :on_audio_chunk,
    :on_input_transcript,
    :on_output_transcript,
    :on_tool_call,
    :on_interrupt,
    :on_turn_complete,
    :on_usage,
    :on_error
  ].freeze

  CHECKPOINT_KEYS = [
    :on_checkpoint,
    :on_turn_complete_checkpoint,
    :on_tool_request_checkpoint,
    :on_tool_response_checkpoint,
    :on_recoverable_error_checkpoint
  ].freeze

  #: (**untyped) -> Riffer::Voice::Agent
  def self.connect(**kwargs)
    options = Riffer::Voice::Agent::ClassConnectOptions.build(kwargs)
    agent = new(**options[:init_options])
    agent.connect(**options[:connect_options])
    agent
  end

  #: (?tool_context: Hash[Symbol, untyped]?, ?auto_handle_tool_calls: bool?, ?tool_executor: ^(tool_call_event: Riffer::Voice::Events::ToolCall, tool_class: singleton(Riffer::Tool)?, arguments: Hash[Symbol, untyped], context: Hash[Symbol, untyped]?, agent: Riffer::Voice::Agent) -> untyped?, ?action_budget: Hash[Symbol | String, untyped]?, ?mutation_classifier: ^(tool_call_event: Riffer::Voice::Events::ToolCall, tool_class: singleton(Riffer::Tool)?, schema_tool: Hash[Symbol | String, untyped]?, arguments: Hash[Symbol, untyped], context: Hash[Symbol, untyped]?, agent: Riffer::Voice::Agent) -> bool?, ?tool_policy: ^(tool_call_event: Riffer::Voice::Events::ToolCall, tool_name: String, tool_class: singleton(Riffer::Tool)?, schema_tool: Hash[Symbol | String, untyped]?, arguments: Hash[Symbol, untyped], mutation_call: bool, context: Hash[Symbol, untyped]?, agent: Riffer::Voice::Agent) -> untyped?, ?approval_callback: ^(tool_call_event: Riffer::Voice::Events::ToolCall, tool_name: String, tool_class: singleton(Riffer::Tool)?, schema_tool: Hash[Symbol | String, untyped]?, arguments: Hash[Symbol, untyped], mutation_call: bool, context: Hash[Symbol, untyped]?, agent: Riffer::Voice::Agent, decision: Hash[Symbol, untyped]) -> untyped?) -> void
  def initialize(
    tool_context: nil,
    auto_handle_tool_calls: nil,
    tool_executor: nil,
    action_budget: nil,
    mutation_classifier: nil,
    tool_policy: nil,
    approval_callback: nil
  )
    state = Riffer::Voice::Agent::InitializationState.build(
      agent_class: self.class,
      tool_context: tool_context,
      auto_handle_tool_calls: auto_handle_tool_calls,
      tool_executor: tool_executor,
      action_budget: action_budget,
      mutation_classifier: mutation_classifier,
      tool_policy: tool_policy,
      approval_callback: approval_callback
    )

    @tool_context = state[:tool_context]
    @auto_handle_tool_calls = state[:auto_handle_tool_calls]
    @model_config = state[:model_config]
    @instructions_text = state[:instructions_text]
    @tools_config = state[:tools_config]
    @tool_executor = state[:tool_executor]
    @action_budget = state[:action_budget]
    @mutation_classifier = state[:mutation_classifier]
    @tool_policy = state[:tool_policy]
    @approval_callback = state[:approval_callback]
    @runtime_config = state[:runtime_config]
    @voice_config = state[:voice_config]
    @connected_tools = [] #: Array[singleton(Riffer::Tool) | Hash[Symbol | String, untyped]]
    @event_callbacks = default_event_callbacks #: Hash[Symbol, Array[^(Riffer::Voice::Events::Base) -> void]]
    @checkpoint_callbacks = default_checkpoint_callbacks #: Hash[Symbol, Array[^(Hash[Symbol, untyped]) -> void]]
    @before_tool_execution_hooks = [] #: Array[^(Hash[Symbol, untyped]) -> void]
    @after_tool_execution_hooks = [] #: Array[^(Hash[Symbol, untyped]) -> void]
    @tool_execution_error_hooks = [] #: Array[^(Hash[Symbol, untyped]) -> void]
    @tool_call_count = 0
    @mutation_tool_call_count = 0
    @active_profile = nil
    @session = nil
  end

  #: (text: String) -> bool
  def send_text_turn(text:)
    current_session.send_text_turn(text: text)
  end

  #: (payload: String, mime_type: String) -> bool
  def send_audio_chunk(payload:, mime_type:)
    current_session.send_audio_chunk(payload: payload, mime_type: mime_type)
  end

  #: (call_id: String, result: untyped) -> bool
  def send_tool_response(call_id:, result:)
    current_session.send_tool_response(call_id: call_id, result: result)
  end

  private
end
