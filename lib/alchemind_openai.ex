defmodule Alchemind.OpenAI do
  @moduledoc """
  OpenAI provider implementation for the Alchemind LLM interface.

  This module implements the Alchemind behaviour for interacting with OpenAI's API.
  """

  @behaviour Alchemind

  @version Mix.Project.config()[:version]

  use RustlerPrecompiled,
    otp_app: :alchemind_openai,
    crate: "alchemind_openai",
    base_url: "https://github.com/bradleygolden/alchemind-openai/releases/download/v#{@version}",
    version: @version,
    targets:
      Enum.uniq(["aarch64-unknown-linux-musl" | RustlerPrecompiled.Config.default_targets()]),
    force_build: System.get_env("ALCHEMIND_OPENAI_BUILD") in ["1", "true"]

  @default_base_url "https://api.openai.com/v1"

  # NIF function declarations
  def create_client(_api_key, _base_url), do: :erlang.nif_error(:nif_not_loaded)
  def complete_chat(_client_resource, _messages, _model), do: :erlang.nif_error(:nif_not_loaded)

  def process_completion_chunk(_client_resource, _messages, _model, _pid, _ref),
    do: :erlang.nif_error(:nif_not_loaded)

  def transcribe_audio(_client_resource, _audio_binary, _opts),
    do: :erlang.nif_error(:nif_not_loaded)

  def text_to_speech(_client_resource, _input, _opts), do: :erlang.nif_error(:nif_not_loaded)

  defmodule Client do
    @moduledoc false

    @type t :: %__MODULE__{
            api_key: String.t(),
            base_url: String.t(),
            model: String.t(),
            rust_client: reference(),
            provider: module()
          }

    @derive {Inspect, except: [:api_key]}
    defstruct [:api_key, :base_url, :model, :rust_client, :provider]
  end

  defmodule Message do
    @moduledoc """
    Defines the Message struct for NIF compatibility.
    """

    defstruct [:role, :content]
  end

  @doc """
  Creates a new OpenAI client.

  ## Options

  - `:api_key` - OpenAI API key (required)
  - `:base_url` - API base URL (default: #{@default_base_url})
  - `:model` - Default model to use (optional, can be overridden in complete calls)

  ## Examples

      iex> Alchemind.OpenAI.new(api_key: "sk-...")
      {:ok, <Rust client resource>}

      iex> Alchemind.OpenAI.new(api_key: "sk-...", model: "gpt-4o")
      {:ok, <Rust client resource>}

  ## Returns

  - `{:ok, client}` - OpenAI client
  - `{:error, reason}` - Error with reason
  """
  @impl Alchemind
  def new(opts \\ []) do
    api_key = opts[:api_key]

    if api_key == nil do
      {:error, "OpenAI API key not provided. Please provide an :api_key option."}
    else
      base_url = opts[:base_url] || @default_base_url

      case create_client(api_key, base_url) do
        rust_client when is_reference(rust_client) ->
          {:ok,
           %Client{
             api_key: api_key,
             base_url: base_url,
             model: opts[:model],
             rust_client: rust_client,
             provider: __MODULE__
           }}

        {:error, reason} ->
          {:error, "Failed to initialize Rust client: #{inspect(reason)}"}
      end
    end
  end

  @doc """
  Completes a conversation using OpenAI's API with optional streaming.

  ## Parameters

  - `client`: OpenAI client created with new/1
  - `messages`: List of messages in the conversation
  - `callback_or_opts`: Callback function for streaming (not supported) or options
  - `opts`: Additional options for the completion request (when callback is provided)

  ## Options

  - `:model` - OpenAI model to use (required unless specified in client)
  - `:temperature` - Controls randomness (0.0 to 2.0)
  - `:max_tokens` - Maximum number of tokens to generate

  ## Examples

  Using model in options:

      iex> {:ok, client} = Alchemind.OpenAI.new(api_key: "sk-...")
      iex> messages = [
      ...>   %{role: :system, content: "You are a helpful assistant."},
      ...>   %{role: :user, content: "Hello, world!"}
      ...> ]
      iex> Alchemind.OpenAI.complete(client, messages, model: "gpt-4o", temperature: 0.7)

  Using default model from client:

      iex> {:ok, client} = Alchemind.OpenAI.new(api_key: "sk-...", model: "gpt-4o")
      iex> messages = [
      ...>   %{role: :system, content: "You are a helpful assistant."},
      ...>   %{role: :user, content: "Hello, world!"}
      ...> ]
      iex> Alchemind.OpenAI.complete(client, messages, temperature: 0.7)

  Note: Streaming is not supported in the direct OpenAI implementation.
  Use OpenAILangChain for streaming support.
  """
  @impl Alchemind
  def complete(client, messages, callback_or_opts \\ [], opts \\ [])

  def complete(client, messages, callback, opts) when is_function(callback, 1) do
    messages = List.wrap(messages)
    model = opts[:model] || client.model

    if model do
      converted_messages =
        Enum.map(messages, fn %{role: role, content: content} ->
          %Message{
            role: to_string(role),
            content: content
          }
        end)

      # Create a unique reference for this stream
      ref = make_ref()

      # Start the streaming process
      spawn_link(fn ->
        # Store these for subsequent processing inside the handler
        stream_context = %{
          client: client.rust_client,
          messages: converted_messages,
          model: model
        }

        # Process the first batch of chunks
        process_completion_chunk(client.rust_client, converted_messages, model, self(), ref)

        # Keep processing until done
        stream_handler(callback, ref, model, stream_context)
      end)

      {:ok, :stream_started}
    else
      {:error,
       %{error: %{message: "Model must be specified in the options for the OpenAI provider."}}}
    end
  end

  def complete(client, messages, opts, additional_opts)
      when is_list(opts) and is_list(additional_opts) do
    messages = List.wrap(messages)
    merged_opts = Keyword.merge(opts, additional_opts)
    model = merged_opts[:model] || client.model

    if model do
      converted_messages =
        Enum.map(messages, fn %{role: role, content: content} ->
          %Message{
            role: to_string(role),
            content: content
          }
        end)

      case complete_chat(client.rust_client, converted_messages, model) do
        content when is_binary(content) ->
          {:ok,
           %{
             id: "rust-client-#{System.os_time(:millisecond)}",
             object: "chat.completion",
             created: System.os_time(:second),
             model: model,
             choices: [
               %{
                 index: 0,
                 message: %{
                   role: :assistant,
                   content: content
                 },
                 finish_reason: "stop"
               }
             ]
           }}

        {:error, reason} ->
          {:error, %{error: %{message: "Rust client error: #{inspect(reason)}"}}}

        _ ->
          {:error, %{error: %{message: "Rust client error"}}}
      end
    else
      {:error,
       %{error: %{message: "Model must be specified in the options for the OpenAI provider."}}}
    end
  end

  @doc """
  Transcribes audio to text using OpenAI's API.

  ## Parameters

  - `client`: OpenAI client created with new/1
  - `audio_binary`: Binary audio data
  - `opts`: Options for the transcription request

  ## Options

  - `:model` - OpenAI transcription model to use (default: "whisper-1")
  - `:language` - Language of the audio (default: nil, auto-detect)
  - `:prompt` - Optional text to guide the model's transcription
  - `:response_format` - Format of the transcript (default: "json")
  - `:temperature` - Controls randomness (0.0 to 1.0, default: 0)

  ## Examples

      iex> {:ok, client} = Alchemind.OpenAI.new(api_key: "sk-...")
      iex> audio_binary = File.read!("audio.mp3")
      iex> Alchemind.OpenAI.transcribe(client, audio_binary, language: "en")
      {:ok, "This is a transcription of the audio."}

  ## Returns

  - `{:ok, text}` - Successful transcription with text
  - `{:error, reason}` - Error with reason
  """
  @impl Alchemind
  def transcribe(client, audio_binary, opts \\ []) do
    case transcribe_audio(client.rust_client, audio_binary, opts) do
      text when is_binary(text) ->
        {:ok, text}

      {:error, reason} ->
        {:error, %{error: %{message: "Transcription failed: #{inspect(reason)}"}}}

      error ->
        {:error, %{error: %{message: "Unexpected transcription error: #{inspect(error)}"}}}
    end
  rescue
    e in ArgumentError ->
      {:error, %{error: %{message: "Invalid arguments for transcription: #{inspect(e.message)}"}}}

    e ->
      {:error, %{error: %{message: "Transcription error: #{inspect(e)}"}}}
  end

  @doc """
  Converts text to speech using OpenAI's API.

  ## Parameters

  - `client`: OpenAI client created with new/1
  - `input`: Text to convert to speech
  - `opts`: Options for the speech request

  ## Options

  - `:model` - OpenAI text-to-speech model to use (default: "gpt-4o-mini-tts")
  - `:voice` - Voice to use (default: "alloy")
  - `:response_format` - Format of the audio (default: "mp3")
  - `:speed` - Speed of the generated audio (optional)

  ## Examples

      iex> {:ok, client} = Alchemind.OpenAI.new(api_key: "sk-...")
      iex> Alchemind.OpenAI.tts(client, "Hello, world!", voice: "echo")
      {:ok, <<binary audio data>>}

  ## Returns

  - `{:ok, audio_binary}` - Successful speech generation with audio binary
  - `{:error, reason}` - Error with reason
  """
  @impl Alchemind
  def speech(client, input, opts \\ []) when is_binary(input) do
    case text_to_speech(client.rust_client, input, opts) do
      audio_data when is_binary(audio_data) ->
        {:ok, audio_data}

      {:error, reason} ->
        {:error, %{error: %{message: "Text-to-speech failed: #{inspect(reason)}"}}}

      error ->
        {:error, %{error: %{message: "Unexpected text-to-speech error: #{inspect(error)}"}}}
    end
  rescue
    e in ArgumentError ->
      {:error,
       %{error: %{message: "Invalid arguments for text-to-speech: #{inspect(e.message)}"}}}

    e ->
      {:error, %{error: %{message: "Text-to-speech error: #{inspect(e)}"}}}
  end

  # Helper function to handle streaming responses from the NIF
  defp stream_handler(callback, ref, model, stream_context) do
    # Set up initial response structure
    response = %{
      id: "rust-client-stream-#{System.os_time(:millisecond)}",
      object: "chat.completion",
      created: System.os_time(:second),
      model: model,
      choices: [
        %{
          index: 0,
          message: %{
            role: :assistant,
            content: ""
          },
          finish_reason: nil
        }
      ]
    }

    stream_handler_loop(callback, ref, response, "", stream_context)
  end

  defp stream_handler_loop(callback, ref, response, accumulated_content, stream_context) do
    receive do
      {:stream_chunk, content, ^ref} ->
        # Call the user's callback with the delta
        callback.(%{content: content})

        # Request the next batch of chunks
        process_completion_chunk(
          stream_context.client,
          stream_context.messages,
          stream_context.model,
          self(),
          ref
        )

        # Continue listening for more chunks
        stream_handler_loop(
          callback,
          ref,
          response,
          accumulated_content <> content,
          stream_context
        )

      {:stream_error, error, ^ref} ->
        # Return an error
        {:error, %{error: %{message: error}}}

      {:stream_done, ^ref} ->
        # When done, return the complete response with accumulated content
        updated_response =
          response
          |> update_in([:choices, Access.at(0), :message, :content], fn _ ->
            accumulated_content
          end)
          |> update_in([:choices, Access.at(0), :finish_reason], fn _ -> "stop" end)

        {:ok, updated_response}
    after
      30_000 ->
        # Timeout after 30 seconds
        {:error, %{error: %{message: "Streaming timeout"}}}
    end
  end
end
