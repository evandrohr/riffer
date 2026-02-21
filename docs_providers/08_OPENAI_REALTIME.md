# OpenAI Realtime Voice Driver

`Riffer::Voice::Drivers::OpenAIRealtime` provides realtime voice sessions using OpenAI Realtime GA websocket APIs.

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

You can also pass `api_key:` directly to the driver constructor.

## Defaults

| Setting | Default |
| ------- | ------- |
| `model` | `gpt-realtime` |
| `endpoint` | `wss://api.openai.com/v1/realtime` |
| Session `input_audio_format` | `pcm16` |
| Session `output_audio_format` | `pcm16` |
| `send_audio_chunk` MIME type | `audio/pcm` |

## Connect

`connect` sends a `session.update` payload and starts a reader task:

```ruby
driver = Riffer::Voice::Drivers::OpenAIRealtime.new

driver.connect(
  system_prompt: "You are a concise voice assistant.",
  tools: [MyTool],
  config: {
    turn_detection: {type: "server_vad"},
    temperature: 0.3
  },
  callbacks: {
    on_output_transcript: ->(event) { puts event.text },
    on_tool_call: ->(event) { puts "Tool: #{event.name}" },
    on_error: ->(event) { warn "#{event.code}: #{event.message}" }
  }
)
```

## Sending Input

```ruby
# Base64-encoded PCM chunk
driver.send_audio_chunk(payload: base64_pcm_chunk, mime_type: "audio/pcm")

# Text turn
driver.send_text_turn(text: "Summarize this call in one sentence.")

# Tool output for a call requested by the model
driver.send_tool_response(call_id: "tool_call_id", result: {ok: true})
```

`send_tool_response` writes both the tool output item and a follow-up `response.create` message.

## Emitted Events

OpenAI payloads are normalized into:

- `AudioChunk`
- `InputTranscript`
- `OutputTranscript`
- `ToolCall`
- `Interrupt`
- `TurnComplete`
- `Usage`
- `Error`

## Closing

```ruby
driver.close(reason: "session_complete")
```

`close` is idempotent and safe to call multiple times.
