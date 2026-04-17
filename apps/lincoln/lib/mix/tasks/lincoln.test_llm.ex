defmodule Mix.Tasks.Lincoln.TestLlm do
  @moduledoc """
  Tests the connection to the configured LLM provider.

  ## Usage

      mix lincoln.test_llm              # Test the configured provider
      mix lincoln.test_llm --provider anthropic
      mix lincoln.test_llm --provider openai

  This task will:
  1. Check if the API key is set for the provider
  2. Send a simple test request
  3. Report success or failure with helpful error messages
  """
  use Mix.Task

  alias Lincoln.Adapters.LLM

  @shortdoc "Tests the connection to the configured LLM provider"

  @impl Mix.Task
  def run(args) do
    Mix.Task.run("app.start")

    {opts, _, _} = OptionParser.parse(args, strict: [provider: :string])
    provider = Keyword.get(opts, :provider) || detect_provider()

    IO.puts("")
    IO.puts("=== Lincoln LLM Connection Test (#{provider}) ===")
    IO.puts("")

    case provider do
      "anthropic" -> test_anthropic()
      "openai" -> test_openai()
      other -> IO.puts("[X] Unknown provider: #{other}. Use 'anthropic' or 'openai'.")
    end
  end

  defp detect_provider do
    case Application.get_env(:lincoln, :llm_adapter) do
      Lincoln.Adapters.LLM.OpenAI -> "openai"
      _ -> "anthropic"
    end
  end

  defp test_anthropic do
    api_key = Application.get_env(:lincoln, :llm)[:api_key]

    if is_nil(api_key) or api_key == "" do
      IO.puts("[X] ANTHROPIC_API_KEY is not set!")
      IO.puts("    Set it in your .env file: ANTHROPIC_API_KEY=sk-ant-...")
      System.halt(1)
    end

    model = Application.get_env(:lincoln, :llm)[:model] || "claude-sonnet-4-20250514"
    IO.puts("[OK] ANTHROPIC_API_KEY set (#{String.slice(api_key, 0, 15)}...)")
    IO.puts("     Model: #{model}")
    IO.puts("")

    run_test(LLM.Anthropic, "Anthropic")
  end

  defp test_openai do
    api_key = Application.get_env(:lincoln, :openai)[:api_key]

    if is_nil(api_key) or api_key == "" do
      IO.puts("[X] OPENAI_API_KEY is not set!")
      IO.puts("    Set it in your .env file: OPENAI_API_KEY=sk-...")
      System.halt(1)
    end

    model = Application.get_env(:lincoln, :openai)[:model] || "gpt-4o"
    IO.puts("[OK] OPENAI_API_KEY set (#{String.slice(api_key, 0, 15)}...)")
    IO.puts("     Model: #{model}")
    IO.puts("")

    run_test(LLM.OpenAI, "OpenAI")
  end

  defp run_test(adapter, provider_name) do
    IO.puts("Testing #{provider_name} API connection...")
    IO.puts("")

    start_time = System.monotonic_time(:millisecond)

    case adapter.complete(
           "Respond with exactly: Hello Lincoln!",
           system: "You are a helpful assistant. Follow instructions precisely."
         ) do
      {:ok, response} ->
        elapsed = System.monotonic_time(:millisecond) - start_time
        IO.puts("[OK] #{provider_name} API connection successful!")
        IO.puts("     Response: #{String.trim(response)}")
        IO.puts("     Latency:  #{elapsed}ms")
        IO.puts("")

      {:error, {:api_error, 401, body}} ->
        IO.puts("[X] Authentication failed! API key appears invalid.")
        IO.puts("    Error: #{inspect(body)}")
        System.halt(1)

      {:error, {:api_error, 429, _body}} ->
        IO.puts("[X] Rate limited! Wait a moment and try again.")
        System.halt(1)

      {:error, {:api_error, status, body}} ->
        IO.puts("[X] API error (status #{status}): #{inspect(body)}")
        System.halt(1)

      {:error, {:request_failed, reason}} ->
        IO.puts("[X] Request failed: #{inspect(reason)}")
        IO.puts("    Check your internet connection.")
        System.halt(1)

      {:error, reason} ->
        IO.puts("[X] Unexpected error: #{inspect(reason)}")
        System.halt(1)
    end
  end
end
