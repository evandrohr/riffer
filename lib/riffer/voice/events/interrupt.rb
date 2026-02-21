# frozen_string_literal: true
# rbs_inline: enabled

# Emitted when the provider signals an interruption.
class Riffer::Voice::Events::Interrupt < Riffer::Voice::Events::Base
  # Reason code or freeform reason string.
  attr_reader :reason #: (String | Symbol)

  #: (reason: (String | Symbol), ?role: Symbol) -> void
  def initialize(reason:, role: :system)
    super(role: role)
    @reason = reason
  end

  #: () -> Hash[Symbol, untyped]
  def to_h
    {role: @role, reason: @reason}
  end
end
