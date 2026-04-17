defmodule Lincoln.Adapters.LLM.OpenAI do
  @moduledoc """
  OpenAI adapter for LLM operations.

  Uses the OpenAI Chat Completions API directly via Req.
  Supports GPT-4o, GPT-4.1, o3, and any model available through
  the OpenAI API (including Azure OpenAI with a custom base URL).
  """
  @behaviour Lincoln.Adapters.LLM

  require Logger

  @default_api_url "https://api.openai.com/v1/chat/completions"

  @impl true
  def chat(messages, opts \\ []) do
    config = get_config(opts)

    body = %{
      model: config.model,
      max_completion_tokens: config.max_tokens,
      messages: format_messages(messages, opts)
    }

    case make_request(body, config) do
      {:ok, %{"choices" => [%{"message" => %{"content" => content}} | _]}} ->
        {:ok, content}

      {:ok, response} ->
        {:error, {:unexpected_response, response}}

      {:error, _} = error ->
        error
    end
  end

  @impl true
  def complete(prompt, opts \\ []) do
    messages = [%{role: "user", content: prompt}]
    chat(messages, opts)
  end

  @impl true
  def extract(prompt, schema, opts \\ []) do
    system_prompt = """
    You are a structured data extractor. Extract the requested information from the text and return it as JSON.
    The JSON must conform to this schema:
    #{Jason.encode!(schema, pretty: true)}

    Return ONLY valid JSON, no additional text or explanation.
    """

    case chat([%{role: "user", content: prompt}], Keyword.put(opts, :system, system_prompt)) do
      {:ok, response} ->
        parse_json_response(response)

      {:error, _} = error ->
        error
    end
  end

  # ============================================================================
  # Private Functions
  # ============================================================================

  defp get_config(opts) do
    app_config = Application.get_env(:lincoln, :openai, [])

    %{
      api_key: Keyword.get(opts, :api_key) || Keyword.get(app_config, :api_key),
      api_url: Keyword.get(opts, :api_url) || Keyword.get(app_config, :api_url, @default_api_url),
      model: Keyword.get(opts, :model) || Keyword.get(app_config, :model, "gpt-4o"),
      max_tokens: Keyword.get(opts, :max_tokens) || Keyword.get(app_config, :max_tokens, 4096)
    }
  end

  defp format_messages(messages, opts) do
    system = Keyword.get(opts, :system)

    system_messages =
      if system do
        [%{"role" => "system", "content" => system}]
      else
        []
      end

    user_messages =
      Enum.map(messages, fn msg ->
        %{
          "role" => to_string(msg[:role] || msg["role"]),
          "content" => msg[:content] || msg["content"]
        }
      end)

    system_messages ++ user_messages
  end

  defp make_request(body, config) do
    headers = [
      {"authorization", "Bearer #{config.api_key}"},
      {"content-type", "application/json"}
    ]

    case Req.post(config.api_url, json: body, headers: headers, receive_timeout: 120_000) do
      {:ok, %{status: 200, body: response_body}} ->
        {:ok, response_body}

      {:ok, %{status: status, body: body}} ->
        Logger.warning("[OpenAI] API error #{status}: #{inspect(body)}")
        {:error, {:api_error, status, body}}

      {:error, reason} ->
        Logger.warning("[OpenAI] Request failed: #{inspect(reason)}")
        {:error, {:request_failed, reason}}
    end
  end

  defp parse_json_response(response) do
    case extract_json(response) do
      {:ok, json_str} ->
        Jason.decode(json_str)

      :error ->
        {:error, :invalid_json}
    end
  end

  defp extract_json(text) do
    cond do
      match = Regex.run(~r/\[[\s\S]*\]/, text) ->
        {:ok, hd(match)}

      match = Regex.run(~r/\{[\s\S]*\}/, text) ->
        {:ok, hd(match)}

      true ->
        :error
    end
  end
end
