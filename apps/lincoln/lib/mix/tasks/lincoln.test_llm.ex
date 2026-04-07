defmodule Mix.Tasks.Lincoln.TestLlm do
  alias Lincoln.Adapters.LLM

  @moduledoc """
  Tests the connection to the Claude API.

  ## Usage

      mix lincoln.test_llm

  This task will:
  1. Check if ANTHROPIC_API_KEY is set
  2. Send a simple test request to the Claude API
  3. Report success or failure with helpful error messages
  """
  use Mix.Task

  @shortdoc "Tests the connection to the Claude API"

  @impl Mix.Task
  def run(_args) do
    # Start the application to load config
    Mix.Task.run("app.start")

    IO.puts("")
    IO.puts("=== Lincoln LLM Connection Test ===")
    IO.puts("")

    # Check for API key from application config (loaded from .env via runtime.exs)
    api_key = Application.get_env(:lincoln, :llm)[:api_key]

    if is_nil(api_key) or api_key == "" do
      IO.puts("[X] ANTHROPIC_API_KEY is not set!")
      IO.puts("")
      IO.puts("Set it in your .env file at the project root:")
      IO.puts("  ANTHROPIC_API_KEY=sk-ant-...")
      IO.puts("")
      System.halt(1)
    end

    IO.puts("[OK] ANTHROPIC_API_KEY is set (#{String.slice(api_key, 0, 15)}...)")
    IO.puts("")
    IO.puts("Testing Claude API connection...")
    IO.puts("")

    start_time = System.monotonic_time(:millisecond)

    case LLM.Anthropic.complete(
           "Respond with exactly: Hello Lincoln!",
           system: "You are a helpful assistant. Follow instructions precisely."
         ) do
      {:ok, response} ->
        elapsed = System.monotonic_time(:millisecond) - start_time

        IO.puts("[OK] API connection successful!")
        IO.puts("")
        IO.puts("Response: #{String.trim(response)}")
        IO.puts("Latency:  #{elapsed}ms")
        IO.puts("")

      {:error, {:api_error, 401, body}} ->
        IO.puts("[X] Authentication failed!")
        IO.puts("")
        IO.puts("Your API key appears to be invalid.")
        IO.puts("Get a new key from: https://console.anthropic.com/")
        IO.puts("")
        IO.puts("Error details: #{inspect(body)}")
        System.halt(1)

      {:error, {:api_error, 429, _body}} ->
        IO.puts("[X] Rate limited!")
        IO.puts("")
        IO.puts("You've exceeded your API rate limit.")
        IO.puts("Wait a moment and try again.")
        System.halt(1)

      {:error, {:api_error, status, body}} ->
        IO.puts("[X] API error (status #{status})")
        IO.puts("")
        IO.puts("Error details: #{inspect(body)}")
        System.halt(1)

      {:error, {:request_failed, reason}} ->
        IO.puts("[X] Request failed!")
        IO.puts("")
        IO.puts("Could not connect to the Anthropic API.")
        IO.puts("Check your internet connection.")
        IO.puts("")
        IO.puts("Error: #{inspect(reason)}")
        System.halt(1)

      {:error, reason} ->
        IO.puts("[X] Unexpected error!")
        IO.puts("")
        IO.puts("Error: #{inspect(reason)}")
        System.halt(1)
    end
  end
end
