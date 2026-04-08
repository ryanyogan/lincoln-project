defmodule Lincoln.MCP.Server do
  @moduledoc """
  Lincoln's MCP server — Streamable HTTP transport.

  Implements MCP protocol (JSON-RPC 2.0) as a Plug, mounted at `/mcp`.
  Exposes Lincoln's cognitive substrate to Claude Code and other MCP clients.
  """

  use Plug.Router
  require Logger

  alias Lincoln.MCP.{Resources, Tools}

  plug(:match)
  plug(Plug.Parsers, parsers: [:json], json_decoder: Jason)
  plug(:dispatch)

  @server_info %{
    name: "lincoln",
    version: "1.0.0"
  }

  @capabilities %{
    tools: %{},
    resources: %{}
  }

  post "/" do
    case conn.body_params do
      %{"jsonrpc" => "2.0", "method" => method, "id" => id} = req ->
        params = Map.get(req, "params", %{})
        result = dispatch_method(method, params)
        send_jsonrpc(conn, id, result)

      %{"jsonrpc" => "2.0", "method" => method} = req ->
        params = Map.get(req, "params", %{})
        _result = dispatch_method(method, params)
        send_resp(conn, 202, "")

      _ ->
        send_jsonrpc_error(conn, nil, -32_600, "Invalid Request")
    end
  end

  delete "/" do
    send_resp(conn, 200, "")
  end

  get "/" do
    send_resp(conn, 405, "Use POST for MCP requests")
  end

  match _ do
    send_resp(conn, 404, "Not found")
  end

  defp dispatch_method("initialize", _params) do
    {:ok,
     %{
       protocolVersion: "2025-03-26",
       capabilities: @capabilities,
       serverInfo: @server_info
     }}
  end

  defp dispatch_method("notifications/initialized", _params), do: {:ok, nil}
  defp dispatch_method("ping", _params), do: {:ok, %{}}

  defp dispatch_method("tools/list", _params) do
    {:ok, %{tools: Tools.list_definitions()}}
  end

  defp dispatch_method("tools/call", %{"name" => name, "arguments" => args}) do
    Tools.call(name, args)
  end

  defp dispatch_method("tools/call", %{"name" => name}) do
    Tools.call(name, %{})
  end

  defp dispatch_method("resources/list", _params) do
    {:ok, %{resources: Resources.list_definitions()}}
  end

  defp dispatch_method("resources/read", %{"uri" => uri}) do
    Resources.read(uri)
  end

  defp dispatch_method(method, _params) do
    {:error, {-32_601, "Method not found: #{method}"}}
  end

  defp send_jsonrpc(conn, id, {:ok, nil}) do
    body = Jason.encode!(%{jsonrpc: "2.0", id: id, result: %{}})
    conn |> put_resp_content_type("application/json") |> send_resp(200, body)
  end

  defp send_jsonrpc(conn, id, {:ok, result}) do
    body = Jason.encode!(%{jsonrpc: "2.0", id: id, result: result})
    conn |> put_resp_content_type("application/json") |> send_resp(200, body)
  end

  defp send_jsonrpc(conn, id, {:error, {code, message}}) do
    send_jsonrpc_error(conn, id, code, message)
  end

  defp send_jsonrpc(conn, id, {:error, message}) when is_binary(message) do
    send_jsonrpc_error(conn, id, -32_000, message)
  end

  defp send_jsonrpc_error(conn, id, code, message) do
    body = Jason.encode!(%{jsonrpc: "2.0", id: id, error: %{code: code, message: message}})
    conn |> put_resp_content_type("application/json") |> send_resp(200, body)
  end
end
