# frozen_string_literal: true
# rbs_inline: enabled

# Emitted when output audio is received from a provider.
class Riffer::Voice::Events::AudioChunk < Riffer::Voice::Events::Base
  # Base64 encoded audio payload.
  attr_reader :payload #: String

  # Provider MIME type for this chunk.
  attr_reader :mime_type #: String

  #: (payload: String, mime_type: String, ?role: Symbol) -> void
  def initialize(payload:, mime_type:, role: :assistant)
    super(role: role)
    @payload = payload
    @mime_type = mime_type
  end

  #: () -> Hash[Symbol, untyped]
  def to_h
    {role: @role, payload: @payload, mime_type: @mime_type}
  end
end
