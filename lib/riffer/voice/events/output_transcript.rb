# frozen_string_literal: true
# rbs_inline: enabled

# Emitted when the provider reports output (assistant) transcription.
class Riffer::Voice::Events::OutputTranscript < Riffer::Voice::Events::Base
  # Transcribed text.
  attr_reader :text #: String

  # Whether this transcript is final.
  attr_reader :is_final #: bool?

  # Additional provider metadata.
  attr_reader :metadata #: Hash[Symbol, untyped]

  #: (text: String, ?is_final: bool?, ?metadata: Hash[Symbol, untyped], ?role: Symbol) -> void
  def initialize(text:, is_final: nil, metadata: {}, role: :assistant)
    super(role: role)
    @text = text
    @is_final = is_final
    @metadata = metadata
  end

  #: () -> Hash[Symbol, untyped]
  def to_h
    hash = {role: @role, text: @text, metadata: @metadata}
    hash[:is_final] = @is_final unless @is_final.nil?
    hash
  end
end
