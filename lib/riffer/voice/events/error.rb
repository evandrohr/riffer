# frozen_string_literal: true
# rbs_inline: enabled

# Emitted when provider or runtime errors occur.
class Riffer::Voice::Events::Error < Riffer::Voice::Events::Base
  # Error code.
  attr_reader :code #: String

  # Error message.
  attr_reader :message #: String

  # Whether retrying may succeed.
  attr_reader :retriable #: bool

  # Additional provider/runtime metadata.
  attr_reader :metadata #: Hash[Symbol, untyped]

  #: (code: String, message: String, ?retriable: bool, ?metadata: Hash[Symbol, untyped], ?role: Symbol) -> void
  def initialize(code:, message:, retriable: false, metadata: {}, role: :system)
    super(role: role)
    @code = code
    @message = message
    @retriable = retriable
    @metadata = metadata
  end

  #: () -> Hash[Symbol, untyped]
  def to_h
    {
      role: @role,
      code: @code,
      message: @message,
      retriable: @retriable,
      metadata: @metadata
    }
  end
end
