# frozen_string_literal: true
# rbs_inline: enabled

require "base64"

module Riffer::Voice::Drivers::OpenaiRealtimeAudio
  private

  #: (payload: String, mime_type: String) -> String
  def normalize_input_audio_payload(payload:, mime_type:)
    mime = mime_type.to_s
    return payload unless mime.include?("audio/pcm")

    source_rate = extract_sample_rate(mime)
    target_rate = Riffer::Voice::Drivers::OpenAIRealtime::DEFAULT_AUDIO_SAMPLE_RATE
    return payload if source_rate.nil? || source_rate == target_rate

    raw = Base64.strict_decode64(payload)
    resampled = resample_pcm16(raw, from_rate: source_rate, to_rate: target_rate)
    Base64.strict_encode64(resampled)
  rescue
    payload
  end

  #: (String) -> Integer?
  def extract_sample_rate(mime_type)
    @sample_rate_cache ||= {} #: Hash[String, Integer?]
    return @sample_rate_cache[mime_type] if @sample_rate_cache.key?(mime_type)

    match = mime_type.match(/rate=(?<rate>\d+)/i)
    rate = if match
      value = match[:rate].to_i
      value.positive? ? value : nil
    end

    cache_limit = Riffer::Voice::Drivers::OpenAIRealtime::SAMPLE_RATE_CACHE_LIMIT
    @sample_rate_cache.shift if @sample_rate_cache.size >= cache_limit
    @sample_rate_cache[mime_type] = rate
  end

  #: (String, from_rate: Integer, to_rate: Integer) -> String
  def resample_pcm16(raw_audio, from_rate:, to_rate:)
    source_samples = raw_audio.unpack("s<*")
    return "".b if source_samples.empty?
    return raw_audio if from_rate == to_rate

    sample_count = [(source_samples.length * to_rate.to_f / from_rate).round, 1].max
    source_max_index = source_samples.length - 1
    resampled = Array.new(sample_count) do |index|
      source_index = (index * from_rate.to_f / to_rate).floor
      source_samples[[source_index, source_max_index].min]
    end

    resampled.pack("s<*")
  end
end
