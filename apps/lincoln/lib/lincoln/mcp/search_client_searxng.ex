defmodule Lincoln.MCP.SearchClient.SearXNG do
  @moduledoc """
  SearXNG-backed implementation of `Lincoln.MCP.SearchClient`.

  SearXNG is a self-hosted meta-search engine that aggregates results from
  Google, DuckDuckGo, Bing, Wikipedia, and dozens of other engines — all
  without API keys or usage limits. This makes it the ideal first hop in
  Lincoln's search cascade: free, unlimited, privacy-respecting.

  Configuration:

      config :lincoln, :searxng,
        base_url: "http://localhost:8888"

  When `:base_url` is absent we behave like the NoOp adapter — return
  `{:ok, []}` so investigation cleanly falls back to its pure-LLM path.

  Failure handling: every transport / API error degrades to `{:ok, []}`
  (logged at debug). An unavailable search must never crash a cognitive cycle.
  """

  @behaviour Lincoln.MCP.SearchClient

  require Logger

  @default_timeout_ms 10_000

  @impl true
  def search(query, opts \\ []) when is_binary(query) do
    config = get_config(opts)

    cond do
      query |> String.trim() |> String.length() == 0 ->
        {:ok, []}

      is_nil(config.base_url) or config.base_url == "" ->
        Logger.debug("[SearXNG] No base_url configured — returning []")
        {:ok, []}

      true ->
        do_search(query, config, opts)
    end
  end

  defp do_search(query, config, opts) do
    url = String.trim_trailing(config.base_url, "/") <> "/search"
    http = Keyword.get(opts, :http) || (&default_get(&1, &2, opts))

    params = [q: query, format: "json", categories: "general"]

    case http.(url, params) do
      {:ok, %{"results" => results}} when is_list(results) ->
        {:ok, normalize(results)}

      {:ok, body} ->
        Logger.debug("[SearXNG] Unexpected body: #{inspect(body, limit: 5)}")
        {:ok, []}

      {:error, reason} ->
        Logger.debug("[SearXNG] Search failed: #{inspect(reason)}")
        {:ok, []}
    end
  end

  defp default_get(url, params, opts) do
    timeout = Keyword.get(opts, :timeout, @default_timeout_ms)

    case Req.get(url, params: params, receive_timeout: timeout) do
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
    app_config = Application.get_env(:lincoln, :searxng, [])

    %{
      base_url: Keyword.get(opts, :base_url) || Keyword.get(app_config, :base_url)
    }
  end
end
