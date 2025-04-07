# NIF for Alchemind.OpenAI

This Rust NIF module provides native integration with OpenAI's API for Alchemind, offering improved performance for key operations.

## Features

- Chat completions with OpenAI models
- Audio transcription (speech-to-text)
- Text-to-speech synthesis

## Dependencies

- `rustler`: For Elixir-Rust interoperability
- `async-openai`: Rust client for OpenAI API
- `tokio`: Asynchronous runtime
- `serde`: For serialization/deserialization

## Usage in Elixir

```elixir
defmodule Alchemind.OpenAI do
  use Rustler, otp_app: :alchemind_openai, crate: "alchemind_openai"

  # NIF function declarations
  def create_client(_api_key, _base_url), do: :erlang.nif_error(:nif_not_loaded)
  def complete_chat(_client_resource, _messages, _model), do: :erlang.nif_error(:nif_not_loaded)
  def transcribe_audio(_client_resource, _audio_binary, _opts), do: :erlang.nif_error(:nif_not_loaded)
  def text_to_speech(_client_resource, _input, _opts), do: :erlang.nif_error(:nif_not_loaded)
  
  # ...Elixir implementation...
end
```

## Examples

```elixir
# Create a client
{:ok, client} = Alchemind.OpenAI.new(api_key: "your-api-key")

# Chat completion
messages = [
  %{role: :system, content: "You are a helpful assistant."},
  %{role: :user, content: "Hello, world!"}
]
{:ok, response} = Alchemind.complete(client, messages, model: "gpt-4o")

# Transcription
audio_binary = File.read!("audio.mp3")
{:ok, text} = Alchemind.transcribe(client, audio_binary)

# Text-to-speech
{:ok, audio_data} = Alchemind.speech(client, "Convert this text to speech")
```
