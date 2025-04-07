defmodule Alchemind.OpenAIStreamingTest do
  @moduledoc """
  This module provides an example for using the streaming functionality of the OpenAI client.
  """

  @doc """
  Example of streaming a chat completion.

  You'll need to set the OPENAI_API_KEY environment variable before running this.

  ## Example

      # Run from the project root with:
      mix run apps/alchemind_openai/test/alchemind_openai_streaming_test.exs
  """
  def run do
    # Check for API key
    api_key = System.get_env("OPENAI_API_KEY")

    if is_nil(api_key) or api_key == "" do
      IO.puts("Error: Please set the OPENAI_API_KEY environment variable.")
      System.halt(1)
    end

    IO.puts("Testing OpenAI streaming...")

    # Create client
    {:ok, client} = Alchemind.OpenAI.new(api_key: api_key)

    # Define messages
    messages = [
      %{role: :system, content: "You are a helpful assistant who responds in a concise manner."},
      %{role: :user, content: "Explain quantum computing in simple terms."}
    ]

    # Set up streaming callback
    callback = fn delta ->
      # Just print the content as it arrives
      if delta.content, do: IO.write(delta.content)
    end

    # Print the prompt
    IO.puts("\nPrompt: Explain quantum computing in simple terms.\n")
    IO.puts("Response:")

    # Call with streaming
    case Alchemind.complete(client, messages, callback, model: "gpt-3.5-turbo") do
      {:ok, _response} ->
        IO.puts("\n\nStreaming completed successfully!")

      {:error, error} ->
        IO.puts("\n\nError: #{inspect(error)}")
    end
  end
end

# Run the example if this file is executed directly
if System.get_env("MIX_ENV") != "test" do
  Alchemind.OpenAIStreamingTest.run()
end
