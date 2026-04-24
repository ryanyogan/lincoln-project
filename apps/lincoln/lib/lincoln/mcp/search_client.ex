defmodule Lincoln.MCP.SearchClient do
  @moduledoc """
  Behaviour for "give me web search results for a query" — Lincoln's outward
  reach for grounding investigation against the live web.

  Implementations are typically thin wrappers over an MCP tool exposed by an
  external server (e.g. a web search MCP). The default `NoOp` implementation
  returns no results so investigation falls back to its pure-LLM path when
  no external search is configured.

  Result shape:

      [
        %{title: "Page title", url: "https://...", snippet: "Excerpt..."},
        ...
      ]
  """

  @type result :: %{title: String.t(), url: String.t() | nil, snippet: String.t() | nil}

  @callback search(query :: String.t(), opts :: keyword()) ::
              {:ok, [result()]} | {:error, term()}
end

defmodule Lincoln.MCP.SearchClient.NoOp do
  @moduledoc """
  Default search client: returns no results. Used when no external web search
  MCP server is configured, so investigation falls back to its pure-LLM path
  cleanly.
  """

  @behaviour Lincoln.MCP.SearchClient

  @impl true
  def search(_query, _opts), do: {:ok, []}
end
