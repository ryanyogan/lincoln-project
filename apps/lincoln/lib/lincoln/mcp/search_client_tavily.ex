defmodule Lincoln.MCP.SearchClient.Tavily do
  @moduledoc """
  Tavily-backed implementation of `Lincoln.MCP.SearchClient`.

  Why Tavily and not a separate MCP server? The `SearchClient` behaviour is
  the abstraction that matters — investigation calls `search/2` and gets a
  list of results. Whether the implementation hits a stdio MCP subprocess or
  Tavily's REST API directly is plumbing. A direct REST adapter keeps the
  dep surface small (just Req, which we already have) and avoids subprocess
  management.

  When Tavily ranks #1 on agent benchmarks (Agent Score 81.36 across
  WebWalker / agentic search evals), going direct is the pragmatic call.

  Configuration:

      config :lincoln, :tavily,
        api_key: System.get_env("TAVILY_API_KEY"),
        search_depth: "basic",     # basic | advanced
        max_results: 5,
        include_answer: false      # set true to include LLM answer in result[0]

  When `:api_key` is absent we behave like the NoOp adapter — return `{:ok, []}`
  so investigation cleanly falls back to its pure-LLM path.

  Failure handling: every transport / API error degrades to `{:ok, []}` (logged
  at debug). An unavailable search must never crash a cognitive cycle.
  """

  @behaviour Lincoln.MCP.SearchClient

  require Logger

  @endpoint "https://api.tavily.com/search"
  @default_timeout_ms 15_000

  @impl true
  def search(query, opts \\ []) when is_binary(query) do
    config = get_config(opts)

    cond do
      query |> String.trim() |> String.length() == 0 ->
        {:ok, []}

      is_nil(config.api_key) or config.api_key == "" ->
        Logger.debug("[Tavily] No API key configured — returning []")
        {:ok, []}

      true ->
        do_search(query, config, opts)
    end
  end

  defp do_search(query, config, opts) do
    body = %{
      api_key: config.api_key,
      query: query,
      search_depth: config.search_depth,
      max_results: Keyword.get(opts, :max_results, config.max_results),
      include_answer: config.include_answer
    }

    http = Keyword.get(opts, :http) || (&default_post(&1, &2, opts))

    case http.(@endpoint, body) do
      {:ok, %{"results" => results}} when is_list(results) ->
        {:ok, normalize(results)}

      {:ok, body} ->
        Logger.debug("[Tavily] Unexpected body: #{inspect(body, limit: 5)}")
        {:ok, []}

      {:error, reason} ->
        Logger.debug("[Tavily] Search failed: #{inspect(reason)}")
        {:ok, []}
    end
  end

  defp default_post(url, body, opts) do
    timeout = Keyword.get(opts, :timeout, @default_timeout_ms)

    case Req.post(url, json: body, receive_timeout: timeout) do
      {:ok, %{status: 200, body: body}} when is_map(body) ->
        {:ok, body}

      {:ok, %{status: status, body: body}} ->
        {:error, {:http_status, status, body}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp normalize(results) do
    results
    |> Enum.map(fn item ->
      %{
        title: stringy(item, ["title"]),
        url: stringy(item, ["url"]),
        snippet: stringy(item, ["content", "snippet", "description"])
      }
    end)
    |> Enum.reject(&(&1.title in [nil, ""]))
  end

  defp stringy(map, keys) do
    Enum.find_value(keys, fn k ->
      case Map.get(map, k) do
        v when is_binary(v) and v != "" -> v
        _ -> nil
      end
    end)
  end

  defp get_config(opts) do
    app_config = Application.get_env(:lincoln, :tavily, [])

    %{
      api_key: Keyword.get(opts, :api_key) || Keyword.get(app_config, :api_key),
      search_depth:
        Keyword.get(opts, :search_depth) || Keyword.get(app_config, :search_depth, "basic"),
      max_results: Keyword.get(opts, :max_results) || Keyword.get(app_config, :max_results, 5),
      include_answer:
        Keyword.get(opts, :include_answer) || Keyword.get(app_config, :include_answer, false)
    }
  end
end
