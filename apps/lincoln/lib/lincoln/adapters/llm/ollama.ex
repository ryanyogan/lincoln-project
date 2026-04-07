defmodule Lincoln.Adapters.LLM.Ollama do
  @moduledoc """
  Ollama LLM adapter for local model inference.

  Implements the Lincoln.Adapters.LLM behaviour using Ollama's REST API
  at http://localhost:11434.

  Ollama API: POST /api/chat with {model, messages, stream: false}
  Health: GET /api/tags
  """

  @behaviour Lincoln.Adapters.LLM

  @default_url "http://localhost:11434"
  @default_model "qwen2.5:7b"

  @impl true
  def chat(messages, opts \\ []) do
    url = config(:service_url, @default_url)
    model = Keyword.get(opts, :model, config(:model, @default_model))

    body = %{
      model: model,
      messages: format_messages(messages),
      stream: false
    }

    case Req.post("#{url}/api/chat", json: body, receive_timeout: 120_000) do
      {:ok, %{status: 200, body: %{"message" => %{"content" => content}}}} ->
        {:ok, content}

      {:ok, %{status: status, body: resp_body}} ->
        {:error, {:api_error, status, resp_body}}

      {:error, %{reason: reason}} when reason in [:econnrefused, :nxdomain, :timeout] ->
        {:error, :ollama_unavailable}

      {:error, reason} ->
        {:error, {:request_failed, reason}}
    end
  end

  @impl true
  def complete(prompt, opts \\ []) do
    chat([%{role: "user", content: prompt}], opts)
  end

  @impl true
  def extract(prompt, schema, opts \\ []) do
    system_prompt = """
    You are a structured data extractor. Extract the requested information from the text and return it as JSON.
    The JSON must conform to this schema:
    #{Jason.encode!(schema, pretty: true)}

    Return ONLY valid JSON, no additional text or explanation.
    """

    case chat(
           [
             %{role: "system", content: system_prompt},
             %{role: "user", content: prompt}
           ],
           opts
         ) do
      {:ok, response} ->
        parse_json_response(response)

      {:error, _} = error ->
        error
    end
  end

  @doc """
  Checks if Ollama is available.

  Returns `:ok` when Ollama is running, or `{:error, :ollama_unavailable}` otherwise.
  """
  def health_check do
    url = config(:service_url, @default_url)

    case Req.get("#{url}/api/tags") do
      {:ok, %{status: 200}} ->
        :ok

      {:error, %{reason: reason}} when reason in [:econnrefused, :nxdomain, :timeout] ->
        {:error, :ollama_unavailable}

      _ ->
        {:error, :ollama_unavailable}
    end
  end

  # ============================================================================
  # Private Functions
  # ============================================================================

  defp config(key, default) do
    Application.get_env(:lincoln, :ollama, [])
    |> Keyword.get(key, default)
  end

  defp format_messages(messages) do
    Enum.map(messages, fn msg ->
      %{
        "role" => to_string(msg[:role] || msg["role"]),
        "content" => msg[:content] || msg["content"]
      }
    end)
  end

  defp parse_json_response(response) do
    case Jason.decode(response) do
      {:ok, data} ->
        {:ok, data}

      {:error, _} ->
        case extract_json(response) do
          {:ok, json_str} -> Jason.decode(json_str)
          :error -> {:error, :invalid_json}
        end
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
