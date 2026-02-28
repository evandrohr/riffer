# frozen_string_literal: true
# rbs_inline: enabled

# Internal option splitter used by Riffer::Voice::Agent.connect.
class Riffer::Voice::Agent::ClassConnectOptions
  INIT_OPTION_KEYS = [
    :tool_context,
    :auto_handle_tool_calls,
    :tool_executor,
    :action_budget,
    :mutation_classifier,
    :tool_policy,
    :approval_callback
  ].freeze

  ALWAYS_INCLUDED_KEYS = [:tool_context].freeze

  #: (Hash[Symbol, untyped]) -> Hash[Symbol, Hash[Symbol, untyped]]
  def self.build(kwargs)
    connect_options = kwargs.dup
    init_options = {}

    INIT_OPTION_KEYS.each do |key|
      value = connect_options.delete(key)
      include_nil_value = ALWAYS_INCLUDED_KEYS.include?(key)
      next if value.nil? && !include_nil_value

      init_options[key] = value
    end

    {init_options: init_options, connect_options: connect_options}
  end
end
