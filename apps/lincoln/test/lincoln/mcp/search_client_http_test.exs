defmodule Lincoln.MCP.SearchClient.HttpTest do
  use ExUnit.Case, async: true

  alias Lincoln.MCP.SearchClient.Http

  @url "https://example.test/mcp"

  describe "search/2 — canonical results" do
    test "extracts a list of {title,url,snippet} entries" do
      http = fn _url, _body ->
        {:ok,
         %{
           "result" => %{
             "results" => [
               %{
                 "title" => "BEAM internals",
                 "url" => "https://example.com/beam",
                 "snippet" => "How the BEAM scheduler works"
               },
               %{"title" => "Erlang OTP", "link" => "https://erlang.org"}
             ]
           }
         }}
      end

      assert {:ok, [first, second]} = Http.search("beam", http: http, url: @url)
      assert first.title == "BEAM internals"
      assert first.url == "https://example.com/beam"
      assert first.snippet == "How the BEAM scheduler works"
      assert second.title == "Erlang OTP"
      assert second.url == "https://erlang.org"
    end
  end

  describe "search/2 — content-text shape" do
    test "decodes JSON wrapped in MCP content/text payloads" do
      inner =
        Jason.encode!(%{
          "results" => [
            %{"title" => "Wrapped result", "url" => "https://wrapped.test"}
          ]
        })

      http = fn _url, _body ->
        {:ok, %{"result" => %{"content" => [%{"type" => "text", "text" => inner}]}}}
      end

      assert {:ok, [%{title: "Wrapped result"}]} = Http.search("anything", http: http, url: @url)
    end
  end

  describe "search/2 — failure paths return [] for graceful fallback" do
    test "no server configured returns empty results" do
      Application.put_env(:lincoln, :mcp_servers, [])
      assert {:ok, []} = Http.search("anything")
    end

    test "transport error returns empty results" do
      http = fn _url, _body -> {:error, :timeout} end
      assert {:ok, []} = Http.search("anything", http: http, url: @url)
    end

    test "RPC error returns empty results" do
      http = fn _url, _body ->
        {:ok, %{"error" => %{"code" => -32_000, "message" => "boom"}}}
      end

      assert {:ok, []} = Http.search("anything", http: http, url: @url)
    end

    test "garbage shape returns empty results" do
      http = fn _url, _body -> {:ok, %{"result" => "totally garbage"}} end
      assert {:ok, []} = Http.search("anything", http: http, url: @url)
    end
  end
end
