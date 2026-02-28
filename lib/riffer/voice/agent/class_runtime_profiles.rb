# frozen_string_literal: true
# rbs_inline: enabled

module Riffer::Voice::Agent::ClassRuntimeProfiles
  include Riffer::Voice::Agent::ClassConfigurationHelpers

  # Gets or sets the default runtime mode used by #connect.
  #
  #: (?Symbol?) -> Symbol?
  def runtime(mode = nil)
    return @runtime if mode.nil?

    unless Riffer::Voice::SUPPORTED_RUNTIMES.include?(mode)
      raise Riffer::ArgumentError, "runtime must be one of: #{Riffer::Voice::SUPPORTED_RUNTIMES.join(", ")}"
    end

    @runtime = mode
  end

  # Gets or sets default connect config merged into #connect(config: ...).
  #
  #: (?Hash[Symbol | String, untyped]?) -> Hash[Symbol | String, untyped]
  def voice_config(config = nil)
    return deep_copy(@voice_config || {}) if config.nil?
    raise Riffer::ArgumentError, "voice_config must be a Hash" unless config.is_a?(Hash)

    @voice_config = deep_copy(config)
  end

  # Gets or sets default automatic voice tool-call handling behavior.
  #
  #: (?bool?) -> bool
  def auto_handle_tool_calls(value = nil)
    if value.nil?
      return true if @auto_handle_tool_calls.nil?

      return @auto_handle_tool_calls
    end

    raise Riffer::ArgumentError, "auto_handle_tool_calls must be true or false" unless value == true || value == false

    @auto_handle_tool_calls = value
  end

  # Defines or retrieves a named profile config bundle.
  #
  # When called with a block, the profile is defined/updated.
  # When called without a block, returns the stored profile hash or nil.
  #
  #: ((String | Symbol), ?{ () -> void }) -> Hash[Symbol, untyped]?
  def profile(name, &block)
    profile_name = normalize_profile_name!(name)

    if block_given?
      definition = Riffer::Voice::Agent::ProfileDefinition.new
      definition.instance_exec(&block)
      profiles = @profiles || {}
      profiles[profile_name] = definition.to_h
      @profiles = profiles
      return deep_copy(@profiles[profile_name])
    end

    deep_copy((@profiles || {})[profile_name])
  end

  # Returns all named profile definitions.
  #
  #: () -> Hash[Symbol, Hash[Symbol, untyped]]
  def profiles
    deep_copy(@profiles || {})
  end
end
