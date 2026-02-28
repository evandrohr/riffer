# frozen_string_literal: true
# rbs_inline: enabled

module Riffer::Voice::Agent::ToolExecution
  # Registers a callback executed before each automatic tool execution.
  #
  #: () { (Hash[Symbol, untyped]) -> void } -> self
  def on_before_tool_execution(&block)
    register_tool_hook(:before, &block)
  end

  # Registers a callback executed after each automatic tool execution.
  #
  #: () { (Hash[Symbol, untyped]) -> void } -> self
  def on_after_tool_execution(&block)
    register_tool_hook(:after, &block)
  end

  # Registers a callback executed for automatic tool execution errors.
  #
  #: () { (Hash[Symbol, untyped]) -> void } -> self
  def on_tool_execution_error(&block)
    register_tool_hook(:error, &block)
  end

  private

  #: (Riffer::Voice::Events::Base) -> void
  def handle_tool_call_event(event)
    return unless event.is_a?(Riffer::Voice::Events::ToolCall)

    emit_checkpoint(:tool_request, {
      call_id: event.call_id,
      tool_name: event.name,
      arguments: event.arguments_hash
    })
    result = execute_tool_call(event)
    serialized_result = serialize_tool_result(result)
    current_session.send_tool_response(call_id: event.call_id, result: serialized_result)
    emit_checkpoint(:tool_response, {
      call_id: event.call_id,
      tool_name: event.name,
      result: serialized_result
    })
    if result.error?
      emit_checkpoint(:recoverable_error, {
        call_id: event.call_id,
        tool_name: event.name,
        error_type: result.error_type,
        error_message: result.error_message
      })
    end
  end

  #: (Riffer::Voice::Events::ToolCall) -> Riffer::Tools::Response
  def execute_tool_call(tool_call_event)
    tool_class = find_tool_class(tool_call_event.name)
    schema_tool = find_schema_tool(tool_call_event.name)
    arguments = parse_tool_arguments(tool_call_event.arguments_hash)
    hook_payload = {
      call_id: tool_call_event.call_id,
      tool_name: tool_call_event.name,
      tool_class: tool_class,
      schema_tool: schema_tool,
      arguments: arguments,
      context: @tool_context,
      event: tool_call_event
    }

    begin
      policy_error = evaluate_dispatch_policy(hook_payload)
      if policy_error
        invoke_tool_hooks(@after_tool_execution_hooks, hook_payload.merge(result: policy_error))
        invoke_tool_hooks(@tool_execution_error_hooks, hook_payload.merge(result: policy_error))
        return policy_error
      end

      invoke_tool_hooks(@before_tool_execution_hooks, hook_payload)
      result = execute_tool_call_with_strategy(
        tool_call_event: tool_call_event,
        tool_class: tool_class,
        schema_tool: schema_tool,
        arguments: arguments
      )
      invoke_tool_hooks(@after_tool_execution_hooks, hook_payload.merge(result: result))
      invoke_tool_hooks(@tool_execution_error_hooks, hook_payload.merge(result: result)) if result.error?
      result
    rescue Riffer::TimeoutError => e
      result = Riffer::Tools::Response.error(e.message, type: :timeout_error)
      safely_invoke_tool_error_hooks(hook_payload, result, e)
      result
    rescue Riffer::ValidationError => e
      result = Riffer::Tools::Response.error(e.message, type: :validation_error)
      safely_invoke_tool_error_hooks(hook_payload, result, e)
      result
    rescue => e
      result = Riffer::Tools::Response.error("Error executing tool: #{e.message}", type: :execution_error)
      safely_invoke_tool_error_hooks(hook_payload, result, e)
      result
    end
  end

  #: (tool_call_event: Riffer::Voice::Events::ToolCall, tool_class: singleton(Riffer::Tool)?, schema_tool: Hash[Symbol | String, untyped]?, arguments: Hash[Symbol, untyped]) -> Riffer::Tools::Response
  def execute_tool_call_with_strategy(tool_call_event:, tool_class:, schema_tool:, arguments:)
    if @tool_executor
      return normalize_tool_executor_result(
        @tool_executor.call(
          tool_call_event: tool_call_event,
          tool_class: tool_class,
          arguments: arguments,
          context: @tool_context,
          agent: self
        )
      )
    end

    if tool_class
      return tool_class.new.call_with_validation(context: @tool_context, **arguments)
    end

    if schema_tool
      return Riffer::Tools::Response.error(
        "Tool '#{tool_call_event.name}' was declared as a schema Hash and requires tool_executor",
        type: :external_tool_executor_required
      )
    end

    Riffer::Tools::Response.error(
      "Unknown tool '#{tool_call_event.name}'",
      type: :unknown_tool
    )
  end

  #: (untyped) -> Riffer::Tools::Response
  def normalize_tool_executor_result(result)
    return result if result.is_a?(Riffer::Tools::Response)

    Riffer::Tools::Response.success(result)
  end

  #: (Riffer::Tools::Response) -> (String | Hash[String, untyped])
  def serialize_tool_result(result)
    return result.content unless result.error?

    {
      "content" => result.content,
      "error" => {
        "type" => result.error_type.to_s,
        "message" => result.error_message
      }
    }
  end

  #: (String) -> singleton(Riffer::Tool)?
  def find_tool_class(name)
    @connected_tools.find do |tool|
      tool.is_a?(Class) && tool <= Riffer::Tool && tool.name == name
    end
  end

  #: (String) -> Hash[Symbol | String, untyped]?
  def find_schema_tool(name)
    @connected_tools.find do |tool|
      next false unless tool.is_a?(Hash)

      schema_tool_names(tool).include?(name)
    end
  end

  #: (Hash[String, untyped]) -> Hash[Symbol, untyped]
  def parse_tool_arguments(arguments)
    return {} if arguments.empty?

    arguments.each_with_object({}) do |(key, value), result|
      result[key.to_sym] = value
    end
  end

  #: (Hash[Symbol | String, untyped]) -> Array[String]
  def schema_tool_names(schema_tool)
    payload = deep_stringify(schema_tool)
    names = []
    names << payload["name"] if payload["name"].is_a?(String) && !payload["name"].empty?
    if payload["function"].is_a?(Hash) && payload["function"]["name"].is_a?(String)
      names << payload["function"]["name"]
    end
    if payload["functionDeclarations"].is_a?(Array)
      payload["functionDeclarations"].each do |declaration|
        name = declaration.is_a?(Hash) ? declaration["name"] : nil
        names << name if name.is_a?(String) && !name.empty?
      end
    end
    names.uniq
  end

  #: (Symbol) { (Hash[Symbol, untyped]) -> void } -> self
  def register_tool_hook(kind, &block)
    raise Riffer::ArgumentError, "on_#{kind}_tool_execution requires a block" unless block_given?

    hooks = case kind
    when :before
      @before_tool_execution_hooks
    when :after
      @after_tool_execution_hooks
    when :error
      @tool_execution_error_hooks
    else
      raise Riffer::ArgumentError, "unknown tool hook kind: #{kind}"
    end
    hooks << block
    self
  end

  #: (Array[^(Hash[Symbol, untyped]) -> void], Hash[Symbol, untyped]) -> void
  def invoke_tool_hooks(hooks, payload)
    hooks.each { |hook| hook.call(payload) }
  end

  #: (Hash[Symbol, untyped], Riffer::Tools::Response, Exception) -> void
  def safely_invoke_tool_error_hooks(hook_payload, result, error)
    invoke_tool_hooks(@tool_execution_error_hooks, hook_payload.merge(result: result, error: error))
  rescue => hook_error
    raise Riffer::Error,
      "on_tool_execution_error callback failed for #{hook_payload[:tool_name]}: #{hook_error.class}: #{hook_error.message}"
  end
end
