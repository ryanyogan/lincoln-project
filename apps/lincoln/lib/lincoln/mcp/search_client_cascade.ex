defmodule Lincoln.MCP.SearchClient.Cascade do
  @moduledoc """
  Cascading search adapter that tries providers in order until one returns
  non-empty results.

  The provider list is read from config at call time:

      config :lincoln, :search_providers,
        [Lincoln.MCP.SearchClient.SearXNG, Lincoln.MCP.SearchClient.Tavily]

  If no config is set, falls back to SearXNG → Tavily (free first, paid
  fallback). Each provider that returns `{:ok, []}` or `{:error, _}` is
  skipped, and the next provider is tried. The first provider that returns
  non-empty results wins.

  This gives Lincoln resilient, multi-provider search with zero code
  changes — just update the config list to reorder or add providers.
  """

  @behaviour Lincoln.MCP.SearchClient

  require Logger

  @impl true
  def search(query, opts \\ []) do
    providers = Keyword.get(opts, :providers) || configured_providers()

    Enum.reduce_while(providers, {:ok, []}, fn provider, _acc ->
      case provider.search(query, opts) do
        {:ok, []} ->
          Logger.debug("[Cascade] #{inspect(provider)} returned [] — trying next")
          {:cont, {:ok, []}}

        {:ok, results} ->
          {:halt, {:ok, results}}

        {:error, reason} ->
          Logger.debug("[Cascade] #{inspect(provider)} failed: #{inspect(reason)} — trying next")
          {:cont, {:ok, []}}
      end
    end)
  end

  defp configured_providers do
    Application.get_env(:lincoln, :search_providers, default_providers())
  end

  defp default_providers do
    [Lincoln.MCP.SearchClient.SearXNG, Lincoln.MCP.SearchClient.Tavily]
  end
end
