defmodule Lincoln.MCP.SearchClient.Http do
  @moduledoc """
  `Lincoln.MCP.SearchClient` implementation that delegates to an external MCP
  server via `Lincoln.MCP.Client`. The server must expose a `search` tool.

  Server-side response shapes accepted (in order tried):

    * `%{"results" => [...]}` — the canonical shape
    * `%{"content" => [%{"type" => "text", "text" => json_string}]}` — the
      shape Anthropic-style MCP tools often use; the inner JSON is decoded
      and treated as the canonical shape
    * a bare list of result-shaped maps

  When the configured server is missing or returns an error, this adapter
  returns `{:ok, []}` so investigation cleanly falls back to its pure-LLM
  path. The error is logged at debug level and not propagated, matching
  the principle that an unavailable external tool should not crash a
  cognitive cycle.
  """

  @behaviour Lincoln.MCP.SearchClient

  alias Lincoln.MCP.Client

  require Logger

  @impl true
  def search(query, opts \\ []) when is_binary(query) do
    server = Keyword.get(opts, :server, :web_search)
    tool = Keyword.get(opts, :tool, "search")
    args = Keyword.get(opts, :arguments, %{query: query})

    case Client.call_tool(server, tool, args, opts) do
      {:ok, result} ->
        {:ok, normalize(result)}

      {:error, :server_not_configured} ->
        Logger.debug("[MCP.SearchClient.Http] No #{server} server configured — returning []")
        {:ok, []}

      {:error, reason} ->
        Logger.debug("[MCP.SearchClient.Http] Search failed: #{inspect(reason)}")
        {:ok, []}
    end
  end

  defp normalize(%{"results" => results}) when is_list(results), do: to_results(results)
  defp normalize(list) when is_list(list), do: to_results(list)

  defp normalize(%{"content" => [%{"type" => "text", "text" => text} | _]}) do
    case Jason.decode(text) do
      {:ok, %{"results" => results}} when is_list(results) -> to_results(results)
      {:ok, list} when is_list(list) -> to_results(list)
      _ -> []
    end
  end

  defp normalize(_), do: []

  defp to_results(list) do
    list
    |> Enum.map(fn item ->
      %{
        title: stringy(item, ["title", "name"]),
        url: stringy(item, ["url", "link"]),
        snippet: stringy(item, ["snippet", "description", "summary", "text"])
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
end
