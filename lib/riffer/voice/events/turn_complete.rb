# frozen_string_literal: true
# rbs_inline: enabled

# Emitted when a provider completes a response turn.
class Riffer::Voice::Events::TurnComplete < Riffer::Voice::Events::Base
  # Additional provider metadata.
  attr_reader :metadata #: Hash[Symbol, untyped]

  #: (?metadata: Hash[Symbol, untyped], ?role: Symbol) -> void
  def initialize(metadata: {}, role: :assistant)
    super(role: role)
    @metadata = metadata
  end

  #: () -> Hash[Symbol, untyped]
  def to_h
    {role: @role, metadata: @metadata}
  end
end
