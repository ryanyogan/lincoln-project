defmodule Lincoln.MCP.SearchClient.FirecrawlTest do
  use ExUnit.Case, async: true

  alias Lincoln.MCP.SearchClient.Firecrawl

  @url "https://example.test/mcp"

  describe "search/2 — canonical results shape" do
    test "extracts {title,url,snippet} entries from a results list" do
      http = fn _url, _body ->
        {:ok,
         %{
           "result" => %{
             "results" => [
               %{
                 "title" => "AGM belief revision primer",
                 "url" => "https://example.com/agm",
                 "markdown" => "# AGM\nPostulates K*1..K*8 describe rational belief change"
               }
             ]
           }
         }}
      end

      assert {:ok, [r]} = Firecrawl.search("agm belief revision", http: http, url: @url)
      assert r.title == "AGM belief revision primer"
      assert r.url == "https://example.com/agm"
      assert r.snippet =~ "Postulates"
    end
  end

  describe "search/2 — real Firecrawl shape: web-keyed results in content/text" do
    test "decodes the {web: [...]} payload Firecrawl actually returns" do
      payload =
        Jason.encode!(%{
          "web" => [
            %{
              "url" => "https://hexdocs.pm/phoenix_live_view",
              "title" => "Phoenix LiveView",
              "description" => "A LiveView is a process that receives events…",
              "markdown" => "# Phoenix LiveView\n\nDocs body…",
              "position" => 1
            }
          ]
        })

      http = fn _url, _body ->
        {:ok, %{"result" => %{"content" => [%{"type" => "text", "text" => payload}]}}}
      end

      assert {:ok, [r]} = Firecrawl.search("phoenix liveview", http: http, url: @url)
      assert r.title == "Phoenix LiveView"
      assert r.url == "https://hexdocs.pm/phoenix_live_view"
      # Markdown wins over description as the snippet because it's richer.
      assert r.snippet =~ "Phoenix LiveView"
    end
  end

  describe "search/2 — content/text JSON shape (legacy / alt keys)" do
    test "decodes data array nested under content/text" do
      payload =
        Jason.encode!(%{
          "data" => [
            %{
              "title" => "First result",
              "url" => "https://first.test",
              "markdown" => "Body of first"
            },
            %{
              "title" => "Second",
              "url" => "https://second.test",
              "description" => "alt snippet field"
            }
          ]
        })

      http = fn _url, _body ->
        {:ok, %{"result" => %{"content" => [%{"type" => "text", "text" => payload}]}}}
      end

      assert {:ok, [first, second]} = Firecrawl.search("anything", http: http, url: @url)
      assert first.title == "First result"
      assert first.url == "https://first.test"
      assert first.snippet == "Body of first"
      assert second.title == "Second"
      assert second.snippet == "alt snippet field"
    end

    test "decodes results-keyed JSON wrapped in content/text too" do
      payload = Jason.encode!(%{"results" => [%{"title" => "Inside text", "url" => "https://x"}]})

      http = fn _url, _body ->
        {:ok, %{"result" => %{"content" => [%{"type" => "text", "text" => payload}]}}}
      end

      assert {:ok, [%{title: "Inside text"}]} = Firecrawl.search("q", http: http, url: @url)
    end
  end

  describe "search/2 — argument shaping" do
    test "passes query, limit, and scrapeOptions to firecrawl_search" do
      parent = self()

      http = fn _url, body ->
        send(parent, {:body, body})
        {:ok, %{"result" => %{"results" => []}}}
      end

      assert {:ok, []} = Firecrawl.search("q", http: http, url: @url, limit: 7)

      assert_receive {:body, body}
      args = get_in(body, [:params, :arguments])
      assert args.query == "q"
      assert args.limit == 7
      assert args.scrapeOptions == %{formats: ["markdown"], onlyMainContent: true}
      assert get_in(body, [:params, :name]) == "firecrawl_search"
    end
  end

  describe "search/2 — graceful failure" do
    test "returns [] when no firecrawl server is configured" do
      Application.put_env(:lincoln, :mcp_servers, [])
      assert {:ok, []} = Firecrawl.search("anything")
    end

    test "returns [] on transport error" do
      http = fn _url, _body -> {:error, :timeout} end
      assert {:ok, []} = Firecrawl.search("anything", http: http, url: @url)
    end

    test "returns [] on RPC error" do
      http = fn _url, _body ->
        {:ok, %{"error" => %{"code" => -32_000, "message" => "rate limited"}}}
      end

      assert {:ok, []} = Firecrawl.search("anything", http: http, url: @url)
    end
  end
end
