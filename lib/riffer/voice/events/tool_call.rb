# frozen_string_literal: true
# rbs_inline: enabled

# Emitted when the provider requests a tool call.
class Riffer::Voice::Events::ToolCall < Riffer::Voice::Events::Base
  # Unique call identifier used for tool responses.
  attr_reader :call_id #: String

  # Tool/function name.
  attr_reader :name #: String

  # Tool call arguments.
  attr_reader :arguments #: Hash[String, untyped]

  # Provider item identifier when available.
  attr_reader :item_id #: String?

  #: (call_id: String, name: String, arguments: Hash[String | Symbol, untyped], ?item_id: String?, ?role: Symbol) -> void
  def initialize(call_id:, name:, arguments:, item_id: nil, role: :assistant)
    super(role: role)
    raise Riffer::ArgumentError, "arguments must be a Hash" unless arguments.is_a?(Hash)

    @call_id = call_id
    @name = name
    @arguments = deep_stringify(arguments)
    @item_id = item_id
  end

  #: () -> Hash[String, untyped]
  def arguments_hash
    @arguments
  end

  #: () -> Hash[Symbol, untyped]
  def to_h
    hash = {
      role: @role,
      call_id: @call_id,
      name: @name,
      arguments: @arguments
    }
    hash[:item_id] = @item_id if @item_id
    hash
  end

  private

  #: (untyped) -> untyped
  def deep_stringify(value)
    case value
    when Hash
      value.each_with_object({}) do |(key, nested), result|
        result[key.to_s] = deep_stringify(nested)
      end
    when Array
      value.map { |nested| deep_stringify(nested) }
    else
      value
    end
  end
end
