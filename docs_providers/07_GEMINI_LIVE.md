# Gemini Live Voice Driver

`Riffer::Voice::Drivers::GeminiLive` provides bidirectional realtime voice over Gemini Live websocket sessions.

## Installation

Add Async websocket dependencies:

```ruby
gem 'async'
gem 'async-http'
gem 'async-websocket'
```

## Configuration

Set the Gemini API key:

```ruby
Riffer.configure do |config|
  config.gemini.api_key = ENV['GEMINI_API_KEY']
end
```

You can also pass `api_key:` directly to the driver constructor.

## Defaults

| Setting | Default |
| ------- | ------- |
| `model` | `gemini-2.5-flash-native-audio-preview-12-2025` |
| `endpoint` | `wss://generativelanguage.googleapis.com/ws/google.ai.generativelanguage.v1beta.GenerativeService.BidiGenerateContent` |
| `send_audio_chunk` MIME type | `audio/pcm;rate=16000` |

If the model does not start with `models/`, the driver prefixes it automatically.

## Connect

`connect` sends a `setup` payload and starts a reader task:

```ruby
driver = Riffer::Voice::Drivers::GeminiLive.new

driver.connect(
  system_prompt: "You are a helpful voice assistant.",
  tools: [MyTool],
  config: {
    generationConfig: {
      responseModalities: ["AUDIO"],
      temperature: 0.2
    }
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
driver.send_audio_chunk(payload: base64_pcm_chunk, mime_type: "audio/pcm;rate=16000")

# Text turn
driver.send_text_turn(text: "Summarize this call in one sentence.")

# Tool output for a call requested by the model
driver.send_tool_response(call_id: "tool_call_id", result: {ok: true})
```

## Tool Definitions

The driver accepts:

- `Riffer::Tool` classes
- Hash declarations in Gemini tool format (`functionDeclarations`)

It sanitizes tool schemas by removing unsupported keys such as `additionalProperties`.

## Emitted Events

Gemini payloads are normalized into:

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
