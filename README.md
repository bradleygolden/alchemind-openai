# Alchemind OpenAI

OpenAI provider implementation for the Alchemind project.

> [!WARNING]  
> This project is currently in early development and should not be used in production environments.

## Overview

This package implements the Alchemind interfaces for OpenAI's API, allowing you to interact with OpenAI models using the consistent Alchemind API. It provides access to OpenAI's chat completion, speech-to-text, and text-to-speech capabilities.

Under the hood, this package uses the rust crate [async-openai](https://github.com/64bit/async-openai).

## Features

| Feature | Support |
|---------|:-------:|
| Chat Completions |  |
| &nbsp;&nbsp;&nbsp;&nbsp;Create chat completion | ✅ |
| &nbsp;&nbsp;&nbsp;&nbsp;Streaming | ✅ |
| Audio |  |
| &nbsp;&nbsp;&nbsp;&nbsp;Create Speech | ✅ |
| &nbsp;&nbsp;&nbsp;&nbsp;Create Transcription | ✅ |

## Installation

The package can be installed by adding `alchemind_openai` to your list of dependencies in `mix.exs`:

```elixir
def deps do
  [
    {:alchemind, "~> 0.1.0-rc1"},
    {:alchemind_openai, "~> 0.1.0-rc.1"}
  ]
end
```

## Development

You can run tests specifically for this package with:

```bash
cd apps/alchemind_openai
mix test
```

## License

See the [LICENSE](LICENSE) file for details.

## Release Process

This package utilizes precompiled Rust NIFs managed by [`rustler_precompiled`](https://hexdocs.pm/rustler_precompiled/). The release process involves GitHub Actions for building the NIFs and a manual step for preparing the Hex package.

**Steps:**

1. Push changes to [mirror repository](https://github.com/bradleygolden/alchemind-openai): `git subtree push --prefix=apps/alchemind_openai openai-mirror <branch_name>`
2. Wait for NIFs to be built
3. Tag the release in the mirror repository
4. Wait for NIFs to be built
5. Run `mix rustler_precompiled.download Alchemind.OpenAI --all` to generate a `checksum-*.exs`
6. Release package to Hex.pm via `mix hex.publish`
