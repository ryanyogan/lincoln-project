defmodule Lincoln.MCP.FetchClient.MCP do
  @moduledoc """
  `Lincoln.MCP.FetchClient` implementation backed by the official
  Anthropic `mcp-server-fetch` MCP server (stdio transport). The server
  exposes a `fetch` tool that takes a `url` and returns the page
  content cleaned up as markdown.

  The response is normalized to the `%{title, url, content}` shape and
  truncated to a configurable byte budget (default 8 KB) so a giant
  page can't blow Investigation's prompt token budget.

  When the configured server is missing or returns an error this
  adapter returns `{:ok, <empty>}` so investigation cleanly degrades —
  matching the pattern from `SearchClient.Http`.
  """

  @behaviour Lincoln.MCP.FetchClient

  alias Lincoln.MCP.Client

  require Logger

  @default_max_bytes 8_192

  @impl true
  def fetch(url, opts \\ []) when is_binary(url) do
    max_bytes = Keyword.get(opts, :max_bytes, @default_max_bytes)
    server = Keyword.get(opts, :server, :fetch)
    tool = Keyword.get(opts, :tool, "fetch")

    args =
      %{url: url}
      |> Map.merge(Keyword.get(opts, :arguments, %{}))

    # Pass opts through (including http/url test injection) but ensure a
    # default timeout if the caller didn't supply one.
    client_opts = Keyword.put_new(opts, :timeout, 30_000)

    case Client.call_tool(server, tool, args, client_opts) do
      {:ok, result} ->
        {:ok, normalize(result, url, max_bytes)}

      {:error, :server_not_configured} ->
        Logger.debug("[MCP.FetchClient.MCP] no #{server} server configured — empty result")
        {:ok, %{title: nil, url: url, content: ""}}

      {:error, reason} ->
        Logger.debug("[MCP.FetchClient.MCP] fetch failed: #{inspect(reason)}")
        {:ok, %{title: nil, url: url, content: ""}}
    end
  end

  defp normalize(%{"content" => parts} = result, url, max_bytes) when is_list(parts) do
    text =
      parts
      |> Enum.filter(&match?(%{"type" => "text"}, &1))
      |> Enum.map_join("\n\n", & &1["text"])

    %{
      title: result["title"] || extract_title(text),
      url: url,
      content: truncate(text, max_bytes)
    }
  end

  defp normalize(text, url, max_bytes) when is_binary(text) do
    %{title: extract_title(text), url: url, content: truncate(text, max_bytes)}
  end

  defp normalize(_, url, _), do: %{title: nil, url: url, content: ""}

  defp extract_title(text) do
    text
    |> String.split("\n", trim: true)
    |> Enum.find(fn line -> String.starts_with?(line, "# ") end)
    |> case do
      nil -> nil
      line -> line |> String.trim_leading("# ") |> String.trim()
    end
  end

  defp truncate(nil, _), do: ""
  defp truncate(text, max_bytes) when byte_size(text) <= max_bytes, do: text
  defp truncate(text, max_bytes), do: binary_part(text, 0, max_bytes) <> "\n\n[…truncated]"
end
