defmodule Lincoln.MCP.SearchClient.Firecrawl do
  @moduledoc """
  `Lincoln.MCP.SearchClient` implementation backed by the Firecrawl MCP
  server (`firecrawl_search` tool).

  Firecrawl combines search + scrape in a single call: when
  `scrapeOptions.formats: ["markdown"]` is set, each result comes back
  with cleaned markdown content alongside the title/url/snippet. This
  is a better fit for Lincoln's investigation flow than search-then-
  fetch as two round trips, and it's why we prefer Firecrawl over
  search-only providers.

  ## Transport

  Firecrawl runs as a stdio subprocess via
  `npx -y firecrawl-mcp`. Configure it under `:lincoln, :mcp_servers`
  with the `:command` + `:env` shape so the API key is exposed to the
  subprocess:

      config :lincoln, :mcp_servers,
        firecrawl: [
          command: "npx",
          args: ["-y", "firecrawl-mcp"],
          env: [{"FIRECRAWL_API_KEY", "fc-..."}]
        ]

  ## Failure semantics

  When the configured server is missing or returns an error this
  adapter returns `{:ok, []}` so investigation cleanly falls back to
  its pure-LLM path. Errors are logged at debug level — an
  unavailable external tool should never crash a cognitive cycle.
  """

  @behaviour Lincoln.MCP.SearchClient

  alias Lincoln.MCP.Client

  require Logger

  @impl true
  def search(query, opts \\ []) when is_binary(query) do
    limit = Keyword.get(opts, :limit, 5)

    args =
      %{
        query: query,
        limit: limit,
        scrapeOptions: %{formats: ["markdown"], onlyMainContent: true}
      }
      |> maybe_put(:lang, Keyword.get(opts, :lang))
      |> maybe_put(:country, Keyword.get(opts, :country))

    case Client.call_tool(:firecrawl, "firecrawl_search", args, opts) do
      {:ok, result} ->
        {:ok, normalize(result)}

      {:error, :server_not_configured} ->
        Logger.debug("[MCP.SearchClient.Firecrawl] no firecrawl server configured — returning []")
        {:ok, []}

      {:error, reason} ->
        Logger.debug("[MCP.SearchClient.Firecrawl] search failed: #{inspect(reason)}")
        {:ok, []}
    end
  end

  defp maybe_put(map, _key, nil), do: map
  defp maybe_put(map, key, value), do: Map.put(map, key, value)

  # Firecrawl wraps results in the standard MCP `content` envelope,
  # with the search payload as a JSON-encoded text block. The actual
  # results live under a top-level `"web"` key (Firecrawl groups by
  # source — `"web"`, `"news"`, `"images"`). The bare `results` /
  # `data` / list shapes are handled too in case the transport decodes
  # the payload before we see it or the tool surface changes.
  defp normalize(%{"web" => results}) when is_list(results), do: to_results(results)
  defp normalize(%{"results" => results}) when is_list(results), do: to_results(results)
  defp normalize(list) when is_list(list), do: to_results(list)

  defp normalize(%{"content" => parts}) when is_list(parts) do
    case extract_search_payload(parts) do
      %{"web" => web} when is_list(web) -> to_results(web)
      %{"data" => data} when is_list(data) -> to_results(data)
      %{"results" => results} when is_list(results) -> to_results(results)
      data when is_list(data) -> to_results(data)
      _ -> []
    end
  end

  defp normalize(_), do: []

  defp extract_search_payload(parts) do
    parts
    |> Enum.filter(&match?(%{"type" => "text"}, &1))
    |> Enum.find_value(fn %{"text" => text} ->
      case Jason.decode(text) do
        {:ok, decoded} -> decoded
        _ -> nil
      end
    end)
  end

  defp to_results(list) do
    list
    |> Enum.map(fn item ->
      %{
        title: stringy(item, ["title", "name"]),
        url: stringy(item, ["url", "link", "sourceURL"]),
        snippet: stringy(item, ["markdown", "description", "snippet", "summary", "text"])
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
