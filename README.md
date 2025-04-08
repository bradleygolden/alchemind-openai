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
| Streaming | ✅ |
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

## Installation

Ensure that the Rust toolchain is installed on your system as this module uses Rustler to compile native code.

## Features

- Chat completions
- Streaming chat completions
- Audio transcription (Whisper API)
- Text-to-speech

## Usage

### Basic Completion

```elixir
# Create a client
{:ok, client} = Alchemind.new(Alchemind.OpenAI, api_key: "your-api-key")

# Define messages
messages = [
  %{role: :system, content: "You are a helpful assistant."},
  %{role: :user, content: "Hello, world!"}
]

# Get a completion
{:ok, response} = Alchemind.complete(client, messages, model: "gpt-3.5-turbo")
IO.puts(response.choices |> Enum.at(0) |> Map.get(:message) |> Map.get(:content))
```

### Streaming Completion

```elixir
# Create a client
{:ok, client} = Alchemind.new(Alchemind.OpenAI, api_key: "your-api-key")

# Define messages
messages = [
  %{role: :system, content: "You are a helpful assistant."},
  %{role: :user, content: "Hello, world!"}
]

# Define a callback function to handle streaming chunks
callback = fn delta ->
  if delta.content, do: IO.write(delta.content)
end

# Get a streaming completion
{:ok, response} = Alchemind.complete(client, messages, callback, model: "gpt-3.5-turbo")
```

### Transcription

```elixir
# Create a client
{:ok, client} = Alchemind.new(Alchemind.OpenAI, api_key: "your-api-key")

# Read audio file
audio_binary = File.read!("audio.mp3")

# Transcribe audio
{:ok, text} = Alchemind.transcribe(client, audio_binary, language: "en")
IO.puts(text)
```

### Text-to-Speech

```elixir
# Create a client
{:ok, client} = Alchemind.new(Alchemind.OpenAI, api_key: "your-api-key")

# Convert text to speech
{:ok, audio_data} = Alchemind.speech(client, "Hello, world!", voice: "echo")

# Save to file
File.write!("output.mp3", audio_data)
```

## Example

An example of using the streaming functionality is available in `test/alchemind_openai_streaming_test.exs`. You can run it with:

```bash
export OPENAI_API_KEY="your-api-key"
mix run apps/alchemind_openai/test/alchemind_openai_streaming_test.exs
```

## Configuration

The following options can be provided when creating a client:

- `:api_key` - OpenAI API key (required)
- `:base_url` - API base URL (default: "https://api.openai.com/v1")
- `:model` - Default model to use (optional, can be overridden in complete calls)

## Running on Server

When running in a Phoenix application, the server will be available at `localhost:4000`.

## License

See the LICENSE file for details.

## Release Process

This package uses GitHub Actions to automate the release process for precompiled NIFs.

1.  **Tagging:** Create and push a git tag (e.g., `git tag v0.1.0 && git push origin v0.1.0`).
2.  **Workflow Trigger:** Pushing a tag triggers the workflow defined in `.github/workflows/release.yml`.
3.  **Build:** The workflow builds the Rust NIFs for various target platforms (defined in the workflow matrix) using the `philss/rustler-precompiled-action`.
4.  **Version:** The package version is automatically extracted from the `version` field in `mix.exs`.
5.  **GitHub Release:** Upon successful builds for all targets for the tagged commit, the workflow uses `softprops/action-gh-release` to automatically create or update a GitHub Release corresponding to the pushed tag. The compiled NIF artifacts (`.tar.gz` files) are attached to this release.

Consumers of this package can then rely on `rustler_precompiled` to download the appropriate precompiled NIF for their platform during dependency fetching, provided a NIF for their target and version exists in a release.

## Repository Mirroring (for Hex.pm)

This application exists within the main `alchemind` monorepo. To publish it as a standalone package on Hex.pm, its history is mirrored to a separate repository using `git subtree`.

**One-time Setup:**

Add the mirror repository as a remote. Replace `<remote_name>` with a name for the remote (e.g., `openai-mirror`) and `<repository_url>` with the actual URL of the mirror repository.

```bash
git remote add <remote_name> <repository_url>
# Example: git remote add openai-mirror git@github.com:your-org/alchemind_openai_mirror.git
```

**Pushing Updates to the Mirror:**

After making changes in the `apps/alchemind_openai` directory within the monorepo that need to be published to the standalone package, push the subtree to the mirror repository:

```bash
git subtree push --prefix=apps/alchemind_openai <remote_name> <branch_name>
# Example: git subtree push --prefix=apps/alchemind_openai openai-mirror main
```

Replace `<remote_name>` with the name chosen during setup (e.g., `openai-mirror`) and `<branch_name>` with the target branch on the mirror repository (usually `main` or `master`).

**Important:** This `git subtree push` needs to be performed *before* tagging a release if the tag is intended for the standalone Hex package published from the mirror repository. The GitHub Actions release workflow detailed above operates on the main monorepo based on tags pushed there, primarily for distributing the precompiled NIFs alongside the monorepo structure. 