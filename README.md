# Alchemind OpenAI

OpenAI provider implementation for the Alchemind project.

## Overview

This package implements the Alchemind interfaces for OpenAI's API, allowing you to interact with OpenAI models using the consistent Alchemind API. It provides access to OpenAI's chat completion, speech-to-text, and text-to-speech capabilities.

## Features

- Chat completions with GPT models
- Speech-to-text transcription
- Text-to-speech synthesis
- Full implementation of the `Alchemind.Provider` behavior

## Capabilities

| Capability | Support |
|------------|:-------:|
| Chat Completions | ✅ |
| Streaming | ❌ |
| Speech to Text | ✅ |
| Text to Speech | ✅ |

## Usage

```elixir
# Create an OpenAI client
{:ok, client} = Alchemind.new(Alchemind.OpenAI, api_key: "your-api-key")

# Define conversation messages
messages = [
  %{role: :system, content: "You are a helpful assistant."},
  %{role: :user, content: "What is the capital of France?"}
]

# Get a completion
{:ok, response} = Alchemind.complete(client, messages, "gpt-4o")

# Extract the assistant's message
assistant_message = 
  response.choices
  |> List.first()
  |> Map.get(:message)
  |> Map.get(:content)

IO.puts("Response: #{assistant_message}")
```

### Speech to Text

```elixir
# Create a client
{:ok, client} = Alchemind.new(Alchemind.OpenAI, api_key: "your-api-key")

# Read audio file
audio_binary = File.read!("speech.mp3")

# Transcribe audio to text
{:ok, text} = Alchemind.transcribe(client, audio_binary, language: "en")

IO.puts("Transcription: #{text}")
```

### Text to Speech

```elixir
# Create a client
{:ok, client} = Alchemind.new(Alchemind.OpenAI, api_key: "your-api-key")

# Convert text to speech
{:ok, audio_binary} = Alchemind.tts(client, "Hello, welcome to Alchemind!", voice: "nova")

# Save the audio to a file
File.write!("output.mp3", audio_binary)
```

## Configuration

You can configure the OpenAI provider when creating a client:

```elixir
{:ok, client} = Alchemind.new(Alchemind.OpenAI, 
  api_key: "your-api-key",
  organization_id: "your-org-id" # Optional
)
```

## Installation

The package can be installed by adding `alchemind_openai` to your list of dependencies in `mix.exs`:

```elixir
def deps do
  [
    {:alchemind, "~> 0.1.0"},
    {:alchemind_openai, "~> 0.1.0"}
  ]
end
```

## Development

You can run tests specifically for this package with:

```bash
cd apps/alchemind_openai
mix test
```

## Documentation

Documentation can be generated with [ExDoc](https://github.com/elixir-lang/ex_doc):

```bash
cd apps/alchemind_openai
mix docs
``` 