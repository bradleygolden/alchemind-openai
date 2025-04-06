defmodule Alchemind.OpenAITest do
  use ExUnit.Case, async: true

  import Req.Test

  describe "new/1" do
    test "returns error when API key is missing" do
      result = Alchemind.OpenAI.new()
      assert {:error, message} = result
      assert message =~ "OpenAI API key not provided"
    end

    test "creates client with API key" do
      {:ok, client} = Alchemind.OpenAI.new(api_key: "test-key")
      assert client.__struct__ == Alchemind.OpenAI.Client
      assert client.api_key == "test-key"
      assert client.base_url == "https://api.openai.com/v1"
      assert is_function(client.http_client)
    end

    test "accepts custom base URL" do
      {:ok, client} =
        Alchemind.OpenAI.new(api_key: "test-key", base_url: "https://custom.openai.com/v1")

      assert client.base_url == "https://custom.openai.com/v1"
    end
  end

  describe "complete/4" do
    test "successfully completes a conversation" do
      messages = [
        %{role: :system, content: "You are a helpful assistant."},
        %{role: :user, content: "Hello, world!"}
      ]

      stub_name = :openai_api_stub

      stub(stub_name, fn conn ->
        assert conn.request_path == "/v1/chat/completions"
        assert conn.host == "api.openai.com"

        auth_header =
          Enum.find(conn.req_headers, fn {name, _} ->
            String.downcase(name) == "authorization"
          end)

        assert auth_header == {"authorization", "Bearer test-key-123"}

        json(conn, %{
          "id" => "chatcmpl-123",
          "object" => "chat.completion",
          "created" => 1_713_704_963,
          "model" => "gpt-4o",
          "choices" => [
            %{
              "index" => 0,
              "message" => %{
                "role" => "assistant",
                "content" => "Hello! How can I assist you today?"
              },
              "finish_reason" => "stop"
            }
          ]
        })
      end)

      http_client = fn url, options ->
        req = Req.new(plug: {Req.Test, stub_name})

        Req.post(req, url: url, headers: options[:headers], json: options[:json])
      end

      {:ok, client} =
        Alchemind.OpenAI.new(
          api_key: "test-key-123",
          http_client: http_client
        )

      result = Alchemind.OpenAI.complete(client, messages, "gpt-4o")

      assert {:ok, response} = result
      assert response.id == "chatcmpl-123"
      assert response.object == "chat.completion"
      assert response.model == "gpt-4o"
      assert length(response.choices) == 1

      assistant_message = List.first(response.choices).message
      assert assistant_message.role == :assistant
      assert assistant_message.content == "Hello! How can I assist you today?"
    end
  end
end
