# Deepgram Voice Agent Sessions

Use Deepgram Voice Agent through the public voice session API:

```ruby
session = Riffer::Voice.connect(
  model: "deepgram/gpt-4o-mini",
  system_prompt: "You are a concise voice assistant.",
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

Set the Deepgram API key:

```ruby
Riffer.configure do |config|
  config.deepgram.api_key = ENV['DEEPGRAM_API_KEY']
end
```

## Session Config

Deepgram-specific connect options are passed through `config:` and are deep-merged into
the initial `Settings` payload.

```ruby
session = Riffer::Voice.connect(
  model: "deepgram/gpt-4o-mini",
  system_prompt: "You are a concise voice assistant.",
  config: {
    "agent" => {
      "think" => {
        "provider" => {
          "type" => "open_ai",
          "model" => "gpt-4o-mini"
        }
      }
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

Deepgram function call requests are surfaced as `Riffer::Voice::Events::ToolCall` only when
`client_side: true` in the request payload. This prevents accidental double execution when
functions are configured server-side.

```ruby
session.events.each do |event|
  next unless event.is_a?(Riffer::Voice::Events::ToolCall)

  result = MyTool.new.call(context: nil, **event.arguments_hash.transform_keys(&:to_sym))
  session.send_tool_response(call_id: event.call_id, result: result)
end
```

Server-sent `FunctionCallResponse` events are emitted as
`Riffer::Voice::Events::OutputTranscript` metadata events. They are not converted into executable
`ToolCall` events.

## Closing

```ruby
session.close
```

`close` is idempotent and safe to call multiple times.
