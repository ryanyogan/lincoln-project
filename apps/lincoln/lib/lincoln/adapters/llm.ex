defmodule Lincoln.Adapters.LLM do
  @moduledoc """
  Behaviour for LLM adapters.

  Defines the interface for interacting with language models.
  This allows swapping between providers (Anthropic, OpenAI, etc.)
  and using mocks in tests.
  """

  @type message :: %{role: String.t(), content: String.t()}
  @type response :: {:ok, String.t()} | {:error, term()}

  @doc """
  Sends a chat completion request to the LLM.
  """
  @callback chat(messages :: [message()], opts :: keyword()) :: response()

  @doc """
  Sends a simple prompt and gets a response.
  """
  @callback complete(prompt :: String.t(), opts :: keyword()) :: response()

  @doc """
  Extracts structured data from text using the LLM.
  """
  @callback extract(prompt :: String.t(), schema :: map(), opts :: keyword()) ::
              {:ok, map()} | {:error, term()}
end

defmodule Lincoln.Adapters.LLM.Anthropic do
  @moduledoc """
  Anthropic Claude adapter for LLM operations.

  Uses the Anthropic API directly from Elixir via Req.
  """
  @behaviour Lincoln.Adapters.LLM

  @api_url "https://api.anthropic.com/v1/messages"

  @impl true
  def chat(messages, opts \\ []) do
    config = get_config(opts)

    body = %{
      model: config.model,
      max_tokens: config.max_tokens,
      messages: format_messages(messages)
    }

    body = maybe_add_system(body, opts)

    case make_request(body, config) do
      {:ok, %{"content" => [%{"text" => text} | _]}} ->
        {:ok, text}

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
    app_config = Application.get_env(:lincoln, :llm, [])

    %{
      api_key: Keyword.get(opts, :api_key) || Keyword.get(app_config, :api_key),
      model:
        Keyword.get(opts, :model) || Keyword.get(app_config, :model, "claude-sonnet-4-20250514"),
      max_tokens: Keyword.get(opts, :max_tokens) || Keyword.get(app_config, :max_tokens, 4096)
    }
  end

  defp format_messages(messages) do
    Enum.map(messages, fn msg ->
      %{
        "role" => to_string(msg[:role] || msg["role"]),
        "content" => msg[:content] || msg["content"]
      }
    end)
  end

  defp maybe_add_system(body, opts) do
    case Keyword.get(opts, :system) do
      nil -> body
      system -> Map.put(body, :system, system)
    end
  end

  defp make_request(body, config) do
    headers = [
      {"x-api-key", config.api_key},
      {"anthropic-version", "2023-06-01"},
      {"content-type", "application/json"}
    ]

    case Req.post(@api_url, json: body, headers: headers, receive_timeout: 120_000) do
      {:ok, %{status: 200, body: response_body}} ->
        {:ok, response_body}

      {:ok, %{status: status, body: body}} ->
        {:error, {:api_error, status, body}}

      {:error, reason} ->
        {:error, {:request_failed, reason}}
    end
  end

  defp parse_json_response(response) do
    # Try to extract JSON from the response
    # Sometimes the model includes extra text before/after JSON
    case extract_json(response) do
      {:ok, json_str} ->
        Jason.decode(json_str)

      :error ->
        {:error, :invalid_json}
    end
  end

  defp extract_json(text) do
    # Try to find JSON in the text - either an array or object
    # First try to find an array (for lists of facts/topics)
    cond do
      # Try array first (more specific for our use cases)
      match = Regex.run(~r/\[[\s\S]*\]/, text) ->
        {:ok, hd(match)}

      # Fall back to object
      match = Regex.run(~r/\{[\s\S]*\}/, text) ->
        {:ok, hd(match)}

      true ->
        :error
    end
  end
end

defmodule Lincoln.Adapters.LLM.Mock do
  @moduledoc """
  Mock LLM adapter for testing.
  """
  @behaviour Lincoln.Adapters.LLM

  @impl true
  def chat(_messages, _opts \\ []) do
    {:ok, "Mock LLM response"}
  end

  @impl true
  def complete(_prompt, _opts \\ []) do
    {:ok, "Mock completion response"}
  end

  @impl true
  def extract(_prompt, _schema, _opts \\ []) do
    {:ok, %{}}
  end
end
