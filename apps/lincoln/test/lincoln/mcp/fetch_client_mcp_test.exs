defmodule Lincoln.MCP.FetchClient.MCPTest do
  use ExUnit.Case, async: true

  alias Lincoln.MCP.FetchClient.MCP, as: FetchMCP

  @url "https://example.test/mcp"
  @page_url "https://docs.example.com/page"

  describe "fetch/2 — canonical content/text shape" do
    test "extracts text and infers title from leading H1" do
      http = fn _url, _body ->
        {:ok,
         %{
           "result" => %{
             "content" => [
               %{"type" => "text", "text" => "# Page Title\n\nBody paragraph."}
             ]
           }
         }}
      end

      assert {:ok, page} = FetchMCP.fetch(@page_url, http: http, url: @url)
      assert page.title == "Page Title"
      assert page.url == @page_url
      assert page.content =~ "Body paragraph"
    end
  end

  describe "fetch/2 — truncation" do
    test "respects max_bytes" do
      big = String.duplicate("a", 20_000)

      http = fn _url, _body ->
        {:ok, %{"result" => %{"content" => [%{"type" => "text", "text" => big}]}}}
      end

      assert {:ok, page} = FetchMCP.fetch(@page_url, http: http, url: @url, max_bytes: 100)
      assert byte_size(page.content) <= 100 + byte_size("\n\n[…truncated]")
      assert page.content =~ "[…truncated]"
    end
  end

  describe "fetch/2 — graceful failure" do
    test "returns empty content when server not configured" do
      Application.put_env(:lincoln, :mcp_servers, [])
      assert {:ok, %{content: ""}} = FetchMCP.fetch(@page_url)
    end

    test "returns empty content on transport error" do
      http = fn _url, _body -> {:error, :timeout} end
      assert {:ok, %{content: ""}} = FetchMCP.fetch(@page_url, http: http, url: @url)
    end

    test "returns empty content on rpc error" do
      http = fn _url, _body -> {:ok, %{"error" => %{"code" => -1, "message" => "x"}}} end
      assert {:ok, %{content: ""}} = FetchMCP.fetch(@page_url, http: http, url: @url)
    end
  end
end
