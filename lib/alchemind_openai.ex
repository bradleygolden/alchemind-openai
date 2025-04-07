defmodule Alchemind.OpenAI do
  @moduledoc """
  OpenAI provider implementation for the Alchemind LLM interface.

  This module implements the Alchemind behaviour for interacting with OpenAI's API.
  """

  @behaviour Alchemind

  @default_base_url "https://api.openai.com/v1"

  defmodule Client do
    @moduledoc """
    Client struct for the OpenAI provider.
    """

    @type t :: %__MODULE__{
            provider: module(),
            api_key: String.t(),
            base_url: String.t(),
            http_client: function(),
            model: String.t() | nil
          }

    defstruct provider: Alchemind.OpenAI,
              api_key: nil,
              base_url: nil,
              http_client: nil,
              model: nil
  end

  @doc """
  Creates a new OpenAI client.

  ## Options

  - `:api_key` - OpenAI API key (required)
  - `:base_url` - API base URL (default: #{@default_base_url})
  - `:http_client` - Function to make HTTP requests (default: Req.post/2)
  - `:model` - Default model to use (optional, can be overridden in complete calls)

  ## Examples

      iex> Alchemind.OpenAI.new(api_key: "sk-...")
      {:ok, %Alchemind.OpenAI.Client{...}}

      iex> Alchemind.OpenAI.new(api_key: "sk-...", model: "gpt-4o")
      {:ok, %Alchemind.OpenAI.Client{...}}

  ## Returns

  - `{:ok, client}` - OpenAI client
  - `{:error, reason}` - Error with reason
  """
  @impl Alchemind
  @spec new(keyword()) :: {:ok, Client.t()} | {:error, String.t()}
  def new(opts \\ []) do
    api_key = opts[:api_key]

    if api_key == nil do
      {:error, "OpenAI API key not provided. Please provide an :api_key option."}
    else
      base_url = opts[:base_url] || @default_base_url
      http_client = opts[:http_client] || (&Req.post/2)
      model = opts[:model]

      client = %Client{
        api_key: api_key,
        base_url: base_url,
        http_client: http_client,
        model: model
      }

      {:ok, client}
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
  @spec complete(Client.t(), [Alchemind.message()], Alchemind.stream_callback() | keyword(), keyword()) ::
          Alchemind.completion_result()
  def complete(client, messages, callback_or_opts \\ [], opts \\ [])

  def complete(%Client{} = _client, _messages, callback, _opts) when is_function(callback, 1) do
    {:error, %{error: %{message: "Streaming is not yet implemented for the OpenAI provider."}}}
  end

  def complete(%Client{} = client, messages, opts, additional_opts) when is_list(opts) and is_list(additional_opts) do
    merged_opts = Keyword.merge(opts, additional_opts)
    model = merged_opts[:model] || client.model

    if model do
      do_complete(client, messages, model, merged_opts)
    else
      {:error, %{error: %{message: "No model specified. Provide a model via the client or as an option."}}}
    end
  end

  defp do_complete(%Client{} = client, messages, model, opts) do
    formatted_messages =
      Enum.map(messages, fn message ->
        %{
          "role" => Atom.to_string(message.role),
          "content" => message.content
        }
      end)

    body =
      %{
        "model" => model,
        "messages" => formatted_messages
      }
      |> maybe_add_option(opts, :temperature)
      |> maybe_add_option(opts, :max_tokens)

    req_options = [
      headers: [
        {"Authorization", "Bearer #{client.api_key}"},
        {"Content-Type", "application/json"}
      ],
      json: body
    ]

    "#{client.base_url}/chat/completions"
    |> client.http_client.(req_options)
    |> handle_response()
  end

  defp maybe_add_option(body, opts, key) do
    case Keyword.get(opts, key) do
      nil -> body
      value -> Map.put(body, Atom.to_string(key), value)
    end
  end

  defp handle_response({:ok, %{status: status, body: body}}) when status in 200..299 do
    {:ok, format_response(body)}
  end

  defp handle_response({:ok, %{status: _, body: body}}) do
    {:error, body}
  end

  defp handle_response({:error, reason}) do
    {:error, reason}
  end

  defp format_response(body) do
    choices =
      Enum.map(body["choices"] || [], fn choice ->
        %{
          index: choice["index"],
          message: %{
            role: String.to_existing_atom(choice["message"]["role"]),
            content: choice["message"]["content"]
          },
          finish_reason: choice["finish_reason"]
        }
      end)

    %{
      id: body["id"],
      object: body["object"],
      created: body["created"],
      model: body["model"],
      choices: choices
    }
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
      iex> Alchemind.OpenAI.transcription(client, audio_binary, language: "en")
      {:ok, "This is a transcription of the audio."}

  ## Returns

  - `{:ok, text}` - Successful transcription with text
  - `{:error, reason}` - Error with reason
  """
  @impl Alchemind
  def transcription(%Client{} = client, audio_binary, opts \\ []) do
    model = opts[:model] || "whisper-1"

    form_data = [
      file: {audio_binary, filename: "audio.webm", content_type: "audio/webm"},
      model: model
    ]

    form_data =
      if opts[:response_format] do
        form_data
      else
        [{:response_format, "text"} | form_data]
      end

    form_data =
      if language = opts[:language] do
        [{:language, language} | form_data]
      else
        form_data
      end

    form_data =
      if prompt = opts[:prompt] do
        [{:prompt, prompt} | form_data]
      else
        form_data
      end

    form_data =
      if temperature = opts[:temperature] do
        [{:temperature, to_string(temperature)} | form_data]
      else
        form_data
      end

    req_options = [
      headers: [
        {"Authorization", "Bearer #{client.api_key}"}
      ],
      form_multipart: form_data,
      connect_options: [timeout: 60_000],
      receive_timeout: 60_000
    ]

    "#{client.base_url}/audio/transcriptions"
    |> client.http_client.(req_options)
    |> handle_transcription_response()
  end

  defp handle_transcription_response({:ok, %{status: status, body: body}}) when status in 200..299 do
    text =
      case body do
        %{"text" => text} -> text
        text when is_binary(text) -> text
        _ -> nil
      end

    if text do
      {:ok, text}
    else
      {:error, "Invalid response format"}
    end
  end

  defp handle_transcription_response({:ok, %{status: _, body: body}}) do
    body =
      if is_binary(body) do
        case Jason.decode(body) do
          {:ok, decoded} -> decoded
          _ -> %{"error" => %{"message" => body}}
        end
      else
        body
      end

    {:error, body}
  end

  defp handle_transcription_response({:error, reason}) do
    {:error, reason}
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
      iex> Alchemind.OpenAI.speech(client, "Hello, world!", voice: "echo")
      {:ok, <<binary audio data>>}

  ## Returns

  - `{:ok, audio_binary}` - Successful speech generation with audio binary
  - `{:error, reason}` - Error with reason
  """
  @impl Alchemind
  def speech(%Client{} = client, input, opts \\ []) when is_binary(input) do
    payload = %{
      model: Keyword.get(opts, :model, "gpt-4o-mini-tts"),
      input: input,
      voice: Keyword.get(opts, :voice, "alloy"),
      response_format: Keyword.get(opts, :response_format, "mp3")
    }

    payload =
      if speed = Keyword.get(opts, :speed) do
        Map.put(payload, :speed, speed)
      else
        payload
      end

    case client.http_client.("#{client.base_url}/audio/speech",
           headers: [
             {"Authorization", "Bearer #{client.api_key}"},
             {"Content-Type", "application/json"}
           ],
           json: payload
         ) do
      {:ok, %{status: 200, body: body}} ->
        {:ok, body}

      {:ok, %{status: status, body: body}} when status in [400, 401, 429, 500] ->
        error_message =
          case body do
            %{"error" => %{"message" => msg}} ->
              msg

            "{\"error\":" <> _ = json_body when is_binary(json_body) ->
              case Jason.decode(json_body) do
                {:ok, %{"error" => %{"message" => msg}}} -> msg
                _ -> "Failed to generate speech (Status: #{status})"
              end

            _ ->
              "Failed to generate speech (Status: #{status})"
          end

        {:error, error_message}

      {:error, reason} ->
        {:error, reason}

      _response ->
        {:error, "Failed to generate speech"}
    end
  end
end
