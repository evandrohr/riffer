# Gemini Live Voice Sessions

Use Gemini Live through the public voice session API:

```ruby
session = Riffer::Voice.connect(
  model: "gemini/gemini-2.5-flash-native-audio-preview-12-2025",
  system_prompt: "You are a helpful voice assistant.",
  runtime: :auto
)
```

## Installation

Add runtime websocket dependencies:

```ruby
# For async/fiber runtime (:async, or :auto with Async task)
gem 'async'
gem 'async-http'
gem 'async-websocket'

# For background/thread runtime (:background, or :auto without Async task)
gem 'websocket-client-simple'
```

## Configuration

Set the Gemini API key:

```ruby
Riffer.configure do |config|
  config.gemini.api_key = ENV['GEMINI_API_KEY']
end
```

## Session Config

Gemini-specific connect options are passed through `config:`:

```ruby
session = Riffer::Voice.connect(
  model: "gemini/gemini-2.5-flash-native-audio-preview-12-2025",
  system_prompt: "You are a helpful voice assistant.",
  config: {
    generationConfig: {
      responseModalities: ["AUDIO"],
      temperature: 0.2
    }
  }
)
```

## Sending Input

```ruby
# Base64-encoded PCM chunk
session.send_audio_chunk(payload: base64_pcm_chunk, mime_type: "audio/pcm;rate=16000")

# Text turn
session.send_text_turn(text: "Summarize this call in one sentence.")
```

## Tool Calls

Gemini tool calls are surfaced as `Riffer::Voice::Events::ToolCall` with hash-only arguments:

```ruby
session.events.each do |event|
  next unless event.is_a?(Riffer::Voice::Events::ToolCall)

  result = MyTool.new.call(context: nil, **event.arguments_hash.transform_keys(&:to_sym))
  session.send_tool_response(call_id: event.call_id, result: result)
end
```

## Closing

```ruby
session.close
```

`close` is idempotent and safe to call multiple times.
