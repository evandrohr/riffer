# frozen_string_literal: true
# rbs_inline: enabled

module Riffer::Voice::Agent::StateSnapshot
  # Exports lightweight orchestration metadata for app-managed resume.
  #
  #: () -> Hash[Symbol, untyped]
  def export_state_snapshot
    {
      active_profile: @active_profile,
      auto_handle_tool_calls: @auto_handle_tool_calls,
      action_budget: deep_copy(@action_budget),
      tool_call_count: @tool_call_count,
      mutation_tool_call_count: @mutation_tool_call_count
    }
  end

  # Imports lightweight orchestration metadata for app-managed resume.
  #
  #: (snapshot: Hash[Symbol | String, untyped]) -> self
  def import_state_snapshot(snapshot:)
    raise Riffer::ArgumentError, "snapshot must be a Hash" unless snapshot.is_a?(Hash)

    normalized = deep_stringify(snapshot)
    apply_auto_handle_tool_calls_snapshot(normalized)
    apply_action_budget_snapshot(normalized)
    apply_tool_call_count_snapshot(normalized)
    apply_mutation_tool_call_count_snapshot(normalized)
    apply_active_profile_snapshot(normalized)
    self
  end

  private

  #: (Hash[String, untyped]) -> void
  def apply_auto_handle_tool_calls_snapshot(snapshot)
    return unless snapshot.key?("auto_handle_tool_calls")

    value = snapshot["auto_handle_tool_calls"]
    valid_value = value == true || value == false
    raise Riffer::ArgumentError, "snapshot auto_handle_tool_calls must be true or false" unless valid_value

    @auto_handle_tool_calls = value
  end

  #: (Hash[String, untyped]) -> void
  def apply_action_budget_snapshot(snapshot)
    return unless snapshot.key?("action_budget")

    @action_budget = validate_action_budget_config!(snapshot["action_budget"], "snapshot action_budget")
  end

  #: (Hash[String, untyped]) -> void
  def apply_tool_call_count_snapshot(snapshot)
    return unless snapshot.key?("tool_call_count")

    @tool_call_count = normalize_snapshot_counter!(snapshot["tool_call_count"], "tool_call_count")
  end

  #: (Hash[String, untyped]) -> void
  def apply_mutation_tool_call_count_snapshot(snapshot)
    return unless snapshot.key?("mutation_tool_call_count")

    @mutation_tool_call_count = normalize_snapshot_counter!(snapshot["mutation_tool_call_count"], "mutation_tool_call_count")
  end

  #: (Hash[String, untyped]) -> void
  def apply_active_profile_snapshot(snapshot)
    return unless snapshot.key?("active_profile")

    profile_value = snapshot["active_profile"]
    @active_profile = profile_value.nil? ? nil : normalize_profile_name!(profile_value, "snapshot active_profile")
  end
end
