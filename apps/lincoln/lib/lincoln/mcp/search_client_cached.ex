defmodule Lincoln.MCP.SearchClient.Cached do
  @moduledoc """
  Cache-through search adapter.

  Sits in front of any other `SearchClient` implementation (typically the
  `Cascade` adapter) and short-circuits with cached results when available.
  Also enforces the per-minute rate limit from `SearchCache`.

  The inner adapter is configurable:

      config :lincoln, :search_inner_adapter, Lincoln.MCP.SearchClient.Cascade

  Defaults to `Cascade` when not set.
  """

  @behaviour Lincoln.MCP.SearchClient

  alias Lincoln.MCP.SearchCache

  @impl true
  def search(query, opts \\ []) do
    if SearchCache.rate_limited?() do
      {:ok, []}
    else
      case SearchCache.get(query) do
        {:ok, cached} ->
          {:ok, cached}

        :miss ->
          case inner_adapter().search(query, opts) do
            {:ok, results} = ok when results != [] ->
              SearchCache.put(query, results)
              ok

            other ->
              other
          end
      end
    end
  end

  defp inner_adapter do
    Application.get_env(:lincoln, :search_inner_adapter, Lincoln.MCP.SearchClient.Cascade)
  end
end
