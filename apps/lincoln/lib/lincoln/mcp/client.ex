defmodule Lincoln.MCP.Client do
  @moduledoc """
  Thin JSON-RPC 2.0 client for outbound MCP servers.

  Lincoln calls into external MCP servers (web search, file system,
  documentation, etc.) by name. Servers are registered under
  `:lincoln, :mcp_servers`, where each entry is either an HTTP server
  (with `:url` and optional `:headers`) or a stdio server (with
  `:command` and optional `:args`):

      config :lincoln, :mcp_servers,
        firecrawl: [
          command: "npx",
          args: ["-y", "firecrawl-mcp"],
          env: [{"FIRECRAWL_API_KEY", "fc-..."}]
        ],
        context7: [
          url: "https://mcp.context7.com/mcp",
          headers: [{"CONTEXT7_API_KEY", "ctx7sk-..."}]
        ],
        fetch: [command: "uvx", args: ["mcp-server-fetch"]]

  ## Transports

  HTTP servers are stateless POSTs (Streamable HTTP transport) — no
  long-lived process, connection pooling handled by Req/Finch.

  Stdio servers are managed by a per-server `Lincoln.MCP.StdioServer`
  GenServer started lazily by `Lincoln.MCP.StdioSupervisor` on first
  lookup. The persistent process is required because the MCP stdio
  spec mandates an `initialize` + `notifications/initialized` handshake
  before any tool call, and the connection is meant to persist for the
  life of the client.

  An optional `:http` opt allows tests to inject a fake HTTP layer:

      Lincoln.MCP.Client.call_tool(:web_search, "search", %{query: "x"},
        http: fn _url, _body -> {:ok, %{"result" => %{"results" => []}}} end)
  """

  require Logger

  @default_timeout_ms 15_000

  @type rpc_result :: {:ok, term()} | {:error, term()}

  @doc """
  Call an MCP tool by name on a configured server.
  """
  @spec call_tool(atom(), String.t(), map(), keyword()) :: rpc_result()
  def call_tool(server, tool, arguments \\ %{}, opts \\ [])
      when is_atom(server) and is_binary(tool) do
    request(server, "tools/call", %{name: tool, arguments: arguments}, opts)
  end

  @doc """
  List the tools an MCP server exposes.
  """
  @spec list_tools(atom(), keyword()) :: rpc_result()
  def list_tools(server, opts \\ []) when is_atom(server) do
    request(server, "tools/list", %{}, opts)
  end

  defp request(server, method, params, opts) do
    case resolve_transport(server, opts) do
      {:http, url, headers} ->
        do_http_request(url, headers, method, params, opts)

      {:stdio, name, cfg} ->
        do_stdio_request(name, cfg, method, params, opts)

      :not_configured ->
        {:error, :server_not_configured}
    end
  end

  defp resolve_transport(server, opts) do
    cond do
      url = Keyword.get(opts, :url) ->
        {:http, url, Keyword.get(opts, :headers, [])}

      cfg = server_config(server) ->
        cond do
          url = cfg[:url] -> {:http, url, cfg[:headers] || []}
          cfg[:command] -> {:stdio, server, cfg}
          true -> :not_configured
        end

      true ->
        :not_configured
    end
  end

  defp do_http_request(url, headers, method, params, opts) do
    body = %{
      jsonrpc: "2.0",
      id: System.unique_integer([:positive]),
      method: method,
      params: params
    }

    http = Keyword.get(opts, :http) || (&default_post(&1, &2, headers, opts))

    case http.(url, body) do
      {:ok, %{"result" => result}} -> {:ok, result}
      {:ok, %{"error" => err}} -> {:error, {:rpc_error, err}}
      {:ok, body} -> {:error, {:unexpected_body, body}}
      {:error, _} = err -> err
    end
  end

  defp default_post(url, body, headers, opts) do
    timeout = Keyword.get(opts, :timeout, @default_timeout_ms)

    # The MCP "Streamable HTTP" transport allows servers to respond with
    # either application/json or text/event-stream. Some servers
    # (Context7's hosted endpoint, for example) reject requests that
    # don't advertise both via Accept and return HTTP 406. Merge a
    # default Accept in unless the caller explicitly set one.
    headers = ensure_accept_header(headers)

    case Req.post(url, json: body, headers: headers, receive_timeout: timeout) do
      {:ok, %{status: 200, body: body}} -> {:ok, decode_sse_or_json(body)}
      {:ok, %{status: status}} -> {:error, {:http_status, status}}
      {:error, reason} -> {:error, reason}
    end
  end

  defp ensure_accept_header(headers) do
    has_accept? =
      Enum.any?(headers, fn
        {k, _} when is_binary(k) -> String.downcase(k) == "accept"
        _ -> false
      end)

    if has_accept?,
      do: headers,
      else: [{"accept", "application/json, text/event-stream"} | headers]
  end

  # Streamable-HTTP MCP servers may reply with a single SSE-framed event
  # whose `data:` line carries the JSON-RPC payload. Req delivers the
  # response body as a string in that case; pull the JSON out so the
  # rest of the pipeline can keep treating responses as decoded maps.
  defp decode_sse_or_json(body) when is_map(body), do: body

  defp decode_sse_or_json(body) when is_binary(body) do
    case extract_sse_data(body) do
      nil ->
        body

      data ->
        case Jason.decode(data) do
          {:ok, decoded} -> decoded
          _ -> body
        end
    end
  end

  defp decode_sse_or_json(other), do: other

  defp extract_sse_data(body) do
    body
    |> String.split("\n", trim: true)
    |> Enum.find_value(fn
      "data: " <> rest -> rest
      "data:" <> rest -> String.trim_leading(rest)
      _ -> nil
    end)
  end

  defp do_stdio_request(name, cfg, method, params, opts) do
    timeout = Keyword.get(opts, :timeout, @default_timeout_ms)

    with {:ok, _pid} <- Lincoln.MCP.StdioSupervisor.ensure_started(name, cfg) do
      Lincoln.MCP.StdioServer.rpc(name, method, params, timeout)
    end
  end

  defp server_config(server) do
    Application.get_env(:lincoln, :mcp_servers, [])
    |> Keyword.get(server)
  end
end
