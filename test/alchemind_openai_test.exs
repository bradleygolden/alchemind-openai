defmodule Alchemind.OpenAITest do
  use ExUnit.Case

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
end
