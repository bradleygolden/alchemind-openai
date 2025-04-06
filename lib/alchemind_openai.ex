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
end
