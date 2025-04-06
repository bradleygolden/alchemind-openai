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
            http_client: function()
          }

    defstruct provider: Alchemind.OpenAI,
              api_key: nil,
              base_url: nil,
              http_client: nil
  end

  @doc """
  Creates a new OpenAI client.

  ## Options

  - `:api_key` - OpenAI API key (required)
  - `:base_url` - API base URL (default: #{@default_base_url})
  - `:http_client` - Function to make HTTP requests (default: Req.post/2)

  ## Examples

      iex> Alchemind.OpenAI.new(api_key: "sk-...")
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

      client = %Client{
        api_key: api_key,
        base_url: base_url,
        http_client: http_client
      }

      {:ok, client}
    end
  end

  @doc """
  Completes a conversation using OpenAI's API.

  ## Parameters

  - `client`: OpenAI client created with new/1
  - `messages`: List of messages in the conversation
  - `model`: OpenAI model to use (e.g. "gpt-4o", "gpt-4o-mini")
  - `opts`: Additional options for the completion request

  ## Options

  - `:temperature` - Controls randomness (0.0 to 2.0)
  - `:max_tokens` - Maximum number of tokens to generate

  ## Example

      iex> {:ok, client} = Alchemind.OpenAI.new(api_key: "sk-...")
      iex> messages = [
      ...>   %{role: :system, content: "You are a helpful assistant."},
      ...>   %{role: :user, content: "Hello, world!"}
      ...> ]
      iex> Alchemind.OpenAI.complete(client, messages, "gpt-4o", temperature: 0.7)
  """
  @impl Alchemind
  @spec complete(Client.t(), [Alchemind.message()], String.t(), keyword()) ::
          Alchemind.completion_result()
  def complete(%Client{} = client, messages, model, opts \\ []) do
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
