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

  describe "complete/3" do
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

      result = Alchemind.OpenAI.complete(client, messages, model: "gpt-4o")

      assert {:ok, response} = result
      assert response.id == "chatcmpl-123"
      assert response.object == "chat.completion"
      assert response.model == "gpt-4o"
      assert length(response.choices) == 1

      assistant_message = List.first(response.choices).message
      assert assistant_message.role == :assistant
      assert assistant_message.content == "Hello! How can I assist you today?"
    end

    test "uses model from client when not specified in options" do
      messages = [
        %{role: :system, content: "You are a helpful assistant."},
        %{role: :user, content: "Hello, world!"}
      ]

      stub_name = :openai_api_stub_default_model

      stub(stub_name, fn conn ->
        assert conn.request_path == "/v1/chat/completions"

        {:ok, body, _conn} = Plug.Conn.read_body(conn)
        body_params = Jason.decode!(body)

        assert body_params["model"] == "gpt-4o"

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
          http_client: http_client,
          model: "gpt-4o"
        )

      result = Alchemind.OpenAI.complete(client, messages)

      assert {:ok, response} = result
      assert response.model == "gpt-4o"
    end
  end

  describe "transcription/3" do
    test "successfully transcribes audio" do
      audio_binary = <<0, 1, 2, 3, 4, 5>>

      stub_name = :openai_transcription_stub

      stub(stub_name, fn conn ->
        assert conn.request_path == "/v1/audio/transcriptions"
        assert conn.host == "api.openai.com"

        content_type = Plug.Conn.get_req_header(conn, "content-type")
        assert Enum.any?(content_type, &String.contains?(&1, "multipart"))

        {:ok, body, _conn} = Plug.Conn.read_body(conn)

        # For multipart form data, we can't easily decode it in the test
        # Instead, just verify that the body is not empty
        assert body != ""

        auth_header =
          Enum.find(conn.req_headers, fn {name, _} ->
            String.downcase(name) == "authorization"
          end)

        assert auth_header == {"authorization", "Bearer test-key-123"}

        json(conn, %{
          "text" => "Hello, this is a transcription."
        })
      end)

      http_client = fn url, options ->
        req = Req.new(plug: {Req.Test, stub_name})
        Req.post(req, url: url, headers: options[:headers], form_multipart: options[:form_multipart])
      end

      {:ok, client} =
        Alchemind.OpenAI.new(
          api_key: "test-key-123",
          http_client: http_client
        )

      result = Alchemind.OpenAI.transcription(client, audio_binary, language: "en")

      assert {:ok, text} = result
      assert text == "Hello, this is a transcription."
    end

    test "returns error on invalid response" do
      audio_binary = <<0, 1, 2, 3, 4, 5>>

      stub_name = :openai_transcription_error_stub

      stub(stub_name, fn conn ->
        Plug.Conn.resp(
          conn,
          400,
          Jason.encode!(%{
            "error" => %{
              "message" => "Invalid file format",
              "type" => "invalid_request_error"
            }
          })
        )
      end)

      http_client = fn url, options ->
        req = Req.new(plug: {Req.Test, stub_name})
        Req.post(req, url: url, headers: options[:headers], form_multipart: options[:form_multipart])
      end

      {:ok, client} =
        Alchemind.OpenAI.new(
          api_key: "test-key-123",
          http_client: http_client
        )

      result = Alchemind.OpenAI.transcription(client, audio_binary)

      assert {:error, error} = result
      assert error["error"]["message"] == "Invalid file format"
    end
  end

  describe "speech/3" do
    test "successfully converts text to speech" do
      input_text = "Hello, this is a test."

      stub_name = :openai_speech_stub

      stub(stub_name, fn conn ->
        assert conn.request_path == "/v1/audio/speech"

        {:ok, body, _conn} = Plug.Conn.read_body(conn)
        body_params = Jason.decode!(body)

        assert body_params["model"] == "gpt-4o-mini-tts"
        assert body_params["input"] == input_text
        assert body_params["voice"] == "alloy"
        assert body_params["response_format"] == "mp3"

        auth_header =
          Enum.find(conn.req_headers, fn {name, _} ->
            String.downcase(name) == "authorization"
          end)

        assert auth_header == {"authorization", "Bearer test-key-123"}

        audio_data = <<0, 1, 2, 3, 4, 5, 6, 7, 8, 9>>
        Plug.Conn.resp(conn, 200, audio_data)
      end)

      http_client = fn url, options ->
        req = Req.new(plug: {Req.Test, stub_name})
        Req.post(req, url: url, headers: options[:headers], json: options[:json])
      end

      {:ok, client} =
        Alchemind.OpenAI.new(
          api_key: "test-key-123",
          http_client: http_client,
          base_url: "https://api.openai.com/v1"
        )

      result = Alchemind.OpenAI.speech(client, input_text)

      assert {:ok, audio_data} = result
      assert is_binary(audio_data)
      assert audio_data == <<0, 1, 2, 3, 4, 5, 6, 7, 8, 9>>
    end

    test "returns error on API failure" do
      input_text = "Hello, this is a test."

      stub_name = :openai_speech_error_stub

      stub(stub_name, fn conn ->
        assert conn.request_path == "/v1/audio/speech"

        Plug.Conn.resp(
          conn,
          400,
          Jason.encode!(%{
            "error" => %{
              "message" => "Invalid input text",
              "type" => "invalid_request_error"
            }
          })
        )
      end)

      http_client = fn url, options ->
        req = Req.new(plug: {Req.Test, stub_name})
        Req.post(req, url: url, headers: options[:headers], json: options[:json])
      end

      {:ok, client} =
        Alchemind.OpenAI.new(
          api_key: "test-key-123",
          http_client: http_client,
          base_url: "https://api.openai.com/v1"
        )

      result = Alchemind.OpenAI.speech(client, input_text)

      assert {:error, error_message} = result
      assert error_message == "Invalid input text"
    end
  end
end
