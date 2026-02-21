# frozen_string_literal: true
# rbs_inline: enabled

# Base class for realtime voice events.
class Riffer::Voice::Events::Base
  # Event role context.
  attr_reader :role #: Symbol

  #: (?role: Symbol) -> void
  def initialize(role: :assistant)
    @role = role
  end

  #: () -> Hash[Symbol, untyped]
  def to_h
    raise NotImplementedError, "Subclasses must implement #to_h"
  end
end
