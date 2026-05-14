defmodule Lincoln.MCP.Context7Client do
  @moduledoc """
  Client for the hosted Context7 MCP server, used to fetch up-to-date
  library documentation in service of Lincoln's self-modification
  pipeline. When Evolution rewrites a file that depends on Phoenix,
  Ecto, LiveView, etc., we ask Context7 for current docs scoped to the
  change at hand and splice the result into the LLM prompt — so the
  generated code reflects the library's current API rather than what
  was true at training cutoff.

  ## Tool surface

  Two calls per lookup, mirroring the Context7 MCP protocol:

    1. `resolve-library-id` — `%{libraryName: "phoenix_live_view",
       query: "streams"}` returns a Context7-compatible library ID
       like `/phoenixframework/phoenix_live_view`.
    2. `query-docs` — `%{libraryId: "/phoenixframework/phoenix_live_view",
       query: "streams"}` returns the relevant docs as text.

  ## Failure semantics

  If the server is unconfigured, the resolve call fails, or no
  matching library is found, this module returns `{:ok, ""}` so
  Evolution can continue without docs. Errors are logged at debug
  level — a documentation lookup failing should never block a
  self-modification cycle.
  """

  require Logger

  @resolve_tool "resolve-library-id"
  @docs_tool "query-docs"
  @default_timeout_ms 20_000

  @doc """
  Look up docs for a library scoped to a topic. Returns
  `{:ok, docs_text}` on success or `{:ok, ""}` on any failure mode.

  Options:
    * `:server` — atom name of the configured MCP server (default `:context7`)
    * `:resolve_tool` — override resolve tool name
    * `:docs_tool` — override docs tool name
    * `:timeout` — per-call HTTP timeout
    * `:client` — override the MCP client module (default `Lincoln.MCP.Client`).
      Tests can inject a stub that implements `call_tool/4`.
  """
  @spec lookup_docs(String.t(), String.t(), keyword()) :: {:ok, String.t()}
  def lookup_docs(library_name, query, opts \\ [])
      when is_binary(library_name) and is_binary(query) do
    server = Keyword.get(opts, :server, :context7)
    resolve_tool = Keyword.get(opts, :resolve_tool, @resolve_tool)
    docs_tool = Keyword.get(opts, :docs_tool, @docs_tool)
    timeout = Keyword.get(opts, :timeout, @default_timeout_ms)
    client = Keyword.get(opts, :client, Lincoln.MCP.Client)

    with {:ok, library_id} <-
           resolve_id(client, server, resolve_tool, library_name, query, timeout),
         {:ok, docs} <- fetch_docs(client, server, docs_tool, library_id, query, timeout) do
      {:ok, docs}
    else
      {:error, reason} ->
        Logger.debug("[MCP.Context7Client] lookup_docs failed: #{inspect(reason)}")
        {:ok, ""}
    end
  end

  defp resolve_id(client, server, tool, library_name, query, timeout) do
    args = %{libraryName: library_name, query: query}

    case client.call_tool(server, tool, args, timeout: timeout) do
      {:ok, result} ->
        case extract_library_id(result) do
          nil -> {:error, :no_library_match}
          id -> {:ok, id}
        end

      {:error, _} = err ->
        err
    end
  end

  defp fetch_docs(client, server, tool, library_id, query, timeout) do
    args = %{libraryId: library_id, query: query}

    case client.call_tool(server, tool, args, timeout: timeout) do
      {:ok, result} ->
        text = extract_text(result)
        if text == "", do: {:error, :empty_docs}, else: {:ok, text}

      {:error, _} = err ->
        err
    end
  end

  defp extract_library_id(%{"libraryId" => id}) when is_binary(id), do: id
  defp extract_library_id(%{"id" => id}) when is_binary(id), do: id

  defp extract_library_id(%{"content" => parts}) when is_list(parts) do
    parts
    |> Enum.filter(&match?(%{"type" => "text"}, &1))
    |> Enum.map_join("\n", & &1["text"])
    |> first_library_id_in_text()
  end

  defp extract_library_id(text) when is_binary(text), do: first_library_id_in_text(text)
  defp extract_library_id(_), do: nil

  defp first_library_id_in_text(text) do
    Regex.run(
      ~r{(?:Context7-compatible library ID:\s*)?(/[\w\.\-]+/[\w\.\-]+(?:/[\w\.\-]+)?)},
      text
    )
    |> case do
      [_, id] -> id
      _ -> nil
    end
  end

  defp extract_text(%{"content" => parts}) when is_list(parts) do
    parts
    |> Enum.filter(&match?(%{"type" => "text"}, &1))
    |> Enum.map_join("\n\n", & &1["text"])
  end

  defp extract_text(text) when is_binary(text), do: text
  defp extract_text(_), do: ""
end
