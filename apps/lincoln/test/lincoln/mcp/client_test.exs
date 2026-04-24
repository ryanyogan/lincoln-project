defmodule Lincoln.MCP.ClientTest do
  use ExUnit.Case, async: true

  alias Lincoln.MCP.Client

  setup do
    prior = Application.get_env(:lincoln, :mcp_servers, [])

    Application.put_env(:lincoln, :mcp_servers, web_search: [url: "https://example.test/mcp"])

    on_exit(fn -> Application.put_env(:lincoln, :mcp_servers, prior) end)

    :ok
  end

  describe "call_tool/4" do
    test "returns the result map on a successful response" do
      http = fn _url, body ->
        assert body[:method] == "tools/call"
        assert body[:params][:name] == "search"
        assert body[:params][:arguments] == %{query: "x"}
        {:ok, %{"jsonrpc" => "2.0", "id" => body[:id], "result" => %{"results" => []}}}
      end

      assert {:ok, %{"results" => []}} =
               Client.call_tool(:web_search, "search", %{query: "x"}, http: http)
    end

    test "returns :server_not_configured when the server name is unknown" do
      assert {:error, :server_not_configured} =
               Client.call_tool(:nonexistent, "search", %{}, http: fn _, _ -> :unused end)
    end

    test "surfaces RPC errors from the server" do
      http = fn _url, _body ->
        {:ok, %{"error" => %{"code" => -32_601, "message" => "Method not found"}}}
      end

      assert {:error, {:rpc_error, %{"code" => -32_601, "message" => "Method not found"}}} =
               Client.call_tool(:web_search, "search", %{}, http: http)
    end

    test "passes through transport errors" do
      http = fn _url, _body -> {:error, :timeout} end
      assert {:error, :timeout} = Client.call_tool(:web_search, "search", %{}, http: http)
    end
  end

  describe "list_tools/2" do
    test "delegates to the same RPC plumbing" do
      http = fn _url, body ->
        assert body[:method] == "tools/list"
        {:ok, %{"result" => %{"tools" => []}}}
      end

      assert {:ok, %{"tools" => []}} = Client.list_tools(:web_search, http: http)
    end
  end
end
