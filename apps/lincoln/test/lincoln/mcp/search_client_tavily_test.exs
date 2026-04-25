defmodule Lincoln.MCP.SearchClient.TavilyTest do
  use ExUnit.Case, async: true

  alias Lincoln.MCP.SearchClient.Tavily

  setup do
    prior = Application.get_env(:lincoln, :tavily, [])

    Application.put_env(:lincoln, :tavily,
      api_key: "test-key",
      search_depth: "basic",
      max_results: 5,
      include_answer: false
    )

    on_exit(fn -> Application.put_env(:lincoln, :tavily, prior) end)

    :ok
  end

  describe "search/2 — happy path" do
    test "extracts title/url/snippet from Tavily's canonical response shape" do
      http = fn url, body ->
        assert url == "https://api.tavily.com/search"
        assert body[:api_key] == "test-key"
        assert body[:query] == "BEAM scheduler"
        assert body[:search_depth] == "basic"
        assert body[:max_results] == 5

        {:ok,
         %{
           "results" => [
             %{
               "title" => "BEAM internals",
               "url" => "https://example.com/beam",
               "content" => "How the BEAM scheduler works...",
               "score" => 0.93
             },
             %{
               "title" => "Erlang OTP",
               "url" => "https://erlang.org",
               "content" => "OTP design principles..."
             }
           ]
         }}
      end

      assert {:ok, [first, second]} = Tavily.search("BEAM scheduler", http: http)
      assert first.title == "BEAM internals"
      assert first.url == "https://example.com/beam"
      assert first.snippet == "How the BEAM scheduler works..."
      assert second.title == "Erlang OTP"
    end

    test "passes max_results override through to the API" do
      http = fn _url, body ->
        assert body[:max_results] == 12
        {:ok, %{"results" => []}}
      end

      assert {:ok, []} = Tavily.search("anything", http: http, max_results: 12)
    end
  end

  describe "search/2 — graceful fallbacks return []" do
    test "no api key configured" do
      Application.put_env(:lincoln, :tavily, [])
      assert {:ok, []} = Tavily.search("anything")
    end

    test "empty / whitespace query short-circuits before HTTP" do
      http = fn _, _ -> flunk("HTTP should not be called for empty query") end
      assert {:ok, []} = Tavily.search("", http: http)
      assert {:ok, []} = Tavily.search("   ", http: http)
    end

    test "transport error" do
      http = fn _, _ -> {:error, :timeout} end
      assert {:ok, []} = Tavily.search("anything", http: http)
    end

    test "non-200 response with body" do
      http = fn _, _ -> {:error, {:http_status, 401, %{"error" => "Invalid API key"}}} end
      assert {:ok, []} = Tavily.search("anything", http: http)
    end

    test "unexpected response shape" do
      http = fn _, _ -> {:ok, %{"unexpected" => "junk"}} end
      assert {:ok, []} = Tavily.search("anything", http: http)
    end

    test "results with empty title are filtered out" do
      http = fn _, _ ->
        {:ok,
         %{
           "results" => [
             %{"title" => "", "url" => "https://x.test"},
             %{"title" => "Real result", "url" => "https://y.test", "content" => "ok"}
           ]
         }}
      end

      assert {:ok, [%{title: "Real result"}]} = Tavily.search("anything", http: http)
    end
  end
end
