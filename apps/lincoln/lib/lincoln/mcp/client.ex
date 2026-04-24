defmodule Lincoln.MCP.Client do
  @moduledoc """
  Thin JSON-RPC 2.0 client for outbound MCP servers over HTTP.

  Lincoln calls into external MCP servers (web search, file system, GitHub,
  etc.) by name. Servers are registered under `:lincoln, :mcp_servers`:

      config :lincoln, :mcp_servers,
        web_search: [url: "https://search.example.com/mcp"]

  Calls are stateless POSTs that follow the MCP "tools/call" / "tools/list"
  shape. The transport is plain Streamable HTTP — the same shape Lincoln's
  hand-rolled inbound MCP server speaks. We avoid a Hermes-style
  long-running client process here because:

    1. Search/tool calls are sporadic and short-lived
    2. Connection pooling is handled by Req/Finch
    3. Stateless clients are simpler to reason about and don't need
       supervision when no MCP server is configured

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
    case server_url(server) do
      nil ->
        {:error, :server_not_configured}

      url ->
        do_request(url, method, params, opts)
    end
  end

  defp do_request(url, method, params, opts) do
    body = %{
      jsonrpc: "2.0",
      id: System.unique_integer([:positive]),
      method: method,
      params: params
    }

    http = Keyword.get(opts, :http) || (&default_post(&1, &2, opts))

    case http.(url, body) do
      {:ok, %{"result" => result}} -> {:ok, result}
      {:ok, %{"error" => err}} -> {:error, {:rpc_error, err}}
      {:ok, body} -> {:error, {:unexpected_body, body}}
      {:error, _} = err -> err
    end
  end

  defp default_post(url, body, opts) do
    timeout = Keyword.get(opts, :timeout, @default_timeout_ms)

    case Req.post(url, json: body, receive_timeout: timeout) do
      {:ok, %{status: 200, body: body}} -> {:ok, body}
      {:ok, %{status: status}} -> {:error, {:http_status, status}}
      {:error, reason} -> {:error, reason}
    end
  end

  defp server_url(server) do
    Application.get_env(:lincoln, :mcp_servers, [])
    |> Keyword.get(server)
    |> case do
      nil -> nil
      cfg -> cfg[:url]
    end
  end
end
