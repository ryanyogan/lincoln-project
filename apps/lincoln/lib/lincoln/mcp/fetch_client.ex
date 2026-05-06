defmodule Lincoln.MCP.FetchClient do
  @moduledoc """
  Behaviour for "read this URL and give me its content as text" — the
  reading half of Lincoln's web senses, paired with `SearchClient`'s
  finding half. Investigation can search with Exa and then read the top
  result with Fetch to ground the LLM more deeply than a snippet alone.

  Implementations are typically thin wrappers over an MCP tool exposed
  by an external server (e.g. the official `mcp-server-fetch` over
  stdio). The default `NoOp` implementation returns an empty body so
  investigation falls back to snippet-only context when no fetch
  server is configured.

  Result shape:

      %{title: "Page title", url: "https://...", content: "Cleaned text..."}
  """

  @type result :: %{
          title: String.t() | nil,
          url: String.t(),
          content: String.t()
        }

  @callback fetch(url :: String.t(), opts :: keyword()) ::
              {:ok, result()} | {:error, term()}
end

defmodule Lincoln.MCP.FetchClient.NoOp do
  @moduledoc """
  Default fetch client: returns empty content. Used when no Fetch MCP
  server is configured, so investigation falls back to its
  search-snippets-only path cleanly.
  """

  @behaviour Lincoln.MCP.FetchClient

  @impl true
  def fetch(url, _opts), do: {:ok, %{title: nil, url: url, content: ""}}
end
