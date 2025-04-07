defmodule Alchemind.OpenAITest do
  use ExUnit.Case

  @api_key System.get_env("OPENAI_API_KEY")
  @skip_integration @api_key == nil or @api_key == ""

  describe "new/1" do
    test "returns error when API key is missing" do
      result = Alchemind.OpenAI.new()
      assert {:error, message} = result
      assert message =~ "OpenAI API key not provided"
    end

    test "create client with rust client reference" do
      {:ok, client} = Alchemind.OpenAI.new(api_key: "test-key")
      assert is_reference(client.rust_client)
    end

    test "creates client with API key" do
      {:ok, client} = Alchemind.OpenAI.new(api_key: "test-key")
      assert client.api_key == "test-key"
    end

    test "creates client with custom base URL" do
      {:ok, client} =
        Alchemind.OpenAI.new(api_key: "test-key", base_url: "https://custom.openai.com/v1")

      assert client.base_url == "https://custom.openai.com/v1"
    end
  end

  describe "complete/3 and complete/4 (streaming)" do
    @tag :integration
    @tag :skip, @skip_integration
    test "streams completion chunks using callback" do
      {:ok, client} = Alchemind.OpenAI.new(api_key: @api_key)
      test_pid = self()

      messages = [
        %{role: :user, content: "Say 'Test'."}
      ]

      callback = fn delta ->
        # Send content back to the test process if it exists
        if content = delta.content, do: send(test_pid, {:chunk, content})
      end

      # Start streaming
      # The result here is immediate, the work happens in a spawned process
      {:ok, :stream_started} = Alchemind.OpenAI.complete(client, messages, callback, model: "gpt-3.5-turbo")

      # Wait for chunks to arrive from the callback
      full_response = receive_chunks()

      # Assert that we received something that looks like the expected word
      assert full_response =~ "Test"
    end

    # Helper to collect chunks sent from the callback
    defp receive_chunks(acc \"\", timeout \\ 10_000) do
      receive do
        {:chunk, content} ->
          receive_chunks(acc <> content, timeout)
      after
        timeout ->
          acc
      end
    end
  end
end
