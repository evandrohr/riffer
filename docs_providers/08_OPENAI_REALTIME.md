# OpenAI Realtime Voice Sessions

Use OpenAI Realtime through the public voice session API:

```ruby
session = Riffer::Voice.connect(
  model: "openai/gpt-realtime",
  system_prompt: "You are a concise voice assistant.",
  runtime: :auto
)
```

## Installation

Add Async websocket dependencies:

```ruby
gem 'async'
gem 'async-http'
gem 'async-websocket'
```

## Configuration

Set the OpenAI API key:

```ruby
Riffer.configure do |config|
  config.openai.api_key = ENV['OPENAI_API_KEY']
end
```

## Session Config

OpenAI-specific connect options are passed through `config:`:

```ruby
session = Riffer::Voice.connect(
  model: "openai/gpt-realtime",
  system_prompt: "You are a concise voice assistant.",
  config: {
    audio: {
      input: {
        turn_detection: {type: "server_vad"}
      }
    },
    temperature: 0.3
  }
)
```

## Sending Input

```ruby
# Base64-encoded PCM chunk
session.send_audio_chunk(payload: base64_pcm_chunk, mime_type: "audio/pcm")

# Text turn
session.send_text_turn(text: "Summarize this call in one sentence.")
```

## Tool Calls

OpenAI tool calls are surfaced as `Riffer::Voice::Events::ToolCall` with hash-only arguments:

```ruby
session.events.each do |event|
  next unless event.is_a?(Riffer::Voice::Events::ToolCall)

  result = MyTool.new.call(context: nil, **event.arguments_hash.transform_keys(&:to_sym))
  session.send_tool_response(call_id: event.call_id, result: result)
end
```

`send_tool_response` forwards tool output and allows the provider runtime to continue generation.

## Closing

```ruby
session.close
```

`close` is idempotent and safe to call multiple times.
