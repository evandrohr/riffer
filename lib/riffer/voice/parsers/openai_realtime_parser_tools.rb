# frozen_string_literal: true
# rbs_inline: enabled

require "json"

# Tool-call extraction and argument normalization for OpenAI realtime payloads.
module Riffer::Voice::Parsers::OpenaiRealtimeParserTools
  include Riffer::Voice::Parsers::OpenaiRealtimeParserConstants

  private

  #: (Hash[String, untyped]) -> Array[Riffer::Voice::Events::Base]
  def parse_tool_call(data)
    call_id = fetch_any(data, KEYS_CALL_ID)
    name = data["name"]
    return [] if call_id.nil? || name.nil?

    [Riffer::Voice::Events::ToolCall.new(
      call_id: call_id.to_s,
      item_id: fetch_any(data, KEYS_ITEM_ID)&.to_s,
      name: name.to_s,
      arguments: parse_arguments(data["arguments"])
    )]
  end

  #: (untyped) -> Hash[String, untyped]
  def parse_arguments(arguments)
    return {} if arguments.nil?
    return deep_stringify(arguments) if arguments.is_a?(Hash)

    parsed = JSON.parse(arguments)
    return deep_stringify(parsed) if parsed.is_a?(Hash)

    warn_invalid_tool_arguments("expected JSON object, got #{parsed.class}")
    {}
  rescue JSON::ParserError => error
    warn_invalid_tool_arguments("json parse failed (#{error.class}: #{error.message})")
    {}
  end

  #: (String) -> void
  def warn_invalid_tool_arguments(reason)
    Warning.warn("[riffer] openai realtime parser normalized invalid tool arguments: #{reason}\n")
  end
end
