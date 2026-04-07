defmodule Lincoln.Autonomy.Research do
  @moduledoc """
  Web research capabilities for autonomous learning.

  Fetches content from the web, summarizes it, and extracts facts.
  Designed to be efficient with tokens while still learning effectively.

  Sources prioritized:
  - Wikipedia (reliable, well-structured)
  - Official documentation
  - Educational sites (.edu)
  - Technical references
  """

  require Logger

  alias Lincoln.Autonomy
  alias Lincoln.Autonomy.WebSource

  @wikipedia_api "https://en.wikipedia.org/api/rest_v1"
  @user_agent "Lincoln/1.0 (Autonomous Learning Agent; contact@example.com)"

  # Maximum content size to process (avoid huge pages)
  @max_content_length 50_000

  # ============================================================================
  # Topic Research
  # ============================================================================

  @doc """
  Researches a topic by finding and fetching relevant content.

  Returns {:ok, research_result} or {:error, reason}
  """
  def research_topic(agent, session, topic, opts \\ []) do
    llm = Keyword.get(opts, :llm, Lincoln.Adapters.LLM.Anthropic)

    with {:ok, url} <- find_source_url(topic.topic),
         :ok <- check_not_fetched(agent, url),
         {:ok, content, title} <- fetch_content(url),
         {:ok, summary} <- summarize_content(content, topic.topic, llm),
         {:ok, facts} <- extract_facts(summary, topic.topic, llm),
         {:ok, related_topics} <- discover_related_topics(summary, topic.topic, llm) do
      # Record the web source
      {:ok, web_source} =
        Autonomy.record_web_source(agent, session, topic, %{
          url: url,
          title: title,
          content_summary: summary,
          content_length: String.length(content),
          facts_extracted: length(facts),
          quality_score: WebSource.domain_quality(URI.parse(url).host)
        })

      {:ok,
       %{
         url: url,
         title: title,
         summary: summary,
         facts: facts,
         related_topics: related_topics,
         web_source: web_source,
         tokens_used: estimate_tokens(content, summary, facts)
       }}
    end
  end

  # ============================================================================
  # URL Discovery
  # ============================================================================

  @doc """
  Finds a good URL to research a topic.
  Prioritizes Wikipedia, then searches for documentation.
  """
  def find_source_url(topic) do
    # First try Wikipedia
    case get_wikipedia_url(topic) do
      {:ok, url} ->
        {:ok, url}

      {:error, _} ->
        # Fall back to a documentation search
        {:ok, build_search_url(topic)}
    end
  end

  defp get_wikipedia_url(topic) do
    # Clean up the topic for Wikipedia
    search_term = topic |> String.replace(" ", "_") |> URI.encode()

    url = "#{@wikipedia_api}/page/summary/#{search_term}"

    case Req.get(url, headers: [{"user-agent", @user_agent}], receive_timeout: 10_000) do
      {:ok, %{status: 200, body: body}} ->
        # Wikipedia API returns the canonical page URL
        case body do
          %{"content_urls" => %{"desktop" => %{"page" => page_url}}} ->
            {:ok, page_url}

          _ ->
            {:error, :no_url_in_response}
        end

      {:ok, %{status: 404}} ->
        {:error, :not_found}

      {:ok, %{status: status}} ->
        {:error, {:http_error, status}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp build_search_url(topic) do
    # Build a documentation search URL
    encoded = URI.encode(topic)
    "https://en.wikipedia.org/wiki/Special:Search?search=#{encoded}"
  end

  # ============================================================================
  # Content Fetching
  # ============================================================================

  defp check_not_fetched(agent, url) do
    if Autonomy.url_fetched?(agent, url) do
      {:error, :already_fetched}
    else
      :ok
    end
  end

  @doc """
  Fetches content from a URL and extracts the main text.
  """
  def fetch_content(url) do
    Logger.debug("Fetching: #{url}")

    case Req.get(url,
           headers: [{"user-agent", @user_agent}],
           receive_timeout: 15_000,
           max_redirects: 3
         ) do
      {:ok, %{status: 200, body: body}} when is_binary(body) ->
        # Extract text content from HTML
        title = extract_title(body)
        text = extract_text_content(body)

        # Truncate if too long
        text =
          if String.length(text) > @max_content_length do
            String.slice(text, 0, @max_content_length) <> "\n[Content truncated...]"
          else
            text
          end

        {:ok, text, title}

      {:ok, %{status: status}} ->
        {:error, {:http_error, status}}

      {:error, reason} ->
        {:error, {:fetch_failed, reason}}
    end
  end

  defp extract_title(html) do
    case Regex.run(~r/<title[^>]*>([^<]+)<\/title>/i, html) do
      [_, title] -> String.trim(title)
      _ -> "Untitled"
    end
  end

  defp extract_text_content(html) do
    html
    # Remove scripts and styles
    |> String.replace(~r/<script[^>]*>[\s\S]*?<\/script>/i, "")
    |> String.replace(~r/<style[^>]*>[\s\S]*?<\/style>/i, "")
    # Remove HTML tags
    |> String.replace(~r/<[^>]+>/, " ")
    # Decode HTML entities
    |> decode_html_entities()
    # Clean up whitespace
    |> String.replace(~r/\s+/, " ")
    |> String.trim()
  end

  defp decode_html_entities(text) do
    text
    |> String.replace("&nbsp;", " ")
    |> String.replace("&amp;", "&")
    |> String.replace("&lt;", "<")
    |> String.replace("&gt;", ">")
    |> String.replace("&quot;", "\"")
    |> String.replace("&#39;", "'")
    |> decode_numeric_entities()
  end

  defp decode_numeric_entities(text) do
    Regex.replace(~r/&#(\d+);/, text, fn _full_match, code ->
      case Integer.parse(code) do
        {num, ""} when num >= 0 and num <= 0x10FFFF ->
          try do
            <<num::utf8>>
          rescue
            _ -> ""
          end

        _ ->
          ""
      end
    end)
  end

  # ============================================================================
  # Content Processing (LLM-based)
  # ============================================================================

  @doc """
  Summarizes content to reduce token usage.
  """
  def summarize_content(content, topic, llm) do
    # If content is already short, skip summarization
    if String.length(content) < 2000 do
      {:ok, content}
    else
      prompt = """
      Summarize the following content about "#{topic}" in 300-500 words.
      Focus on key facts, concepts, and relationships.
      Preserve specific details like numbers, names, and definitions.

      Content:
      #{String.slice(content, 0, 8000)}

      Summary:
      """

      case llm.complete(prompt, max_tokens: 800) do
        {:ok, summary} -> {:ok, String.trim(summary)}
        error -> error
      end
    end
  end

  @doc """
  Extracts structured facts from content.
  """
  def extract_facts(content, topic, llm) do
    prompt = """
    Extract 3-7 key facts from this content about "#{topic}".
    Each fact should be:
    - Self-contained (understandable without context)
    - Specific and verifiable
    - Worth remembering

    Content:
    #{content}

    IMPORTANT: Return ONLY a valid JSON array, nothing else. No markdown, no explanation.
    Format exactly like this example:
    [{"fact": "First fact here", "confidence": 0.9}, {"fact": "Second fact here", "confidence": 0.85}]

    Return [] if no clear facts can be extracted.
    """

    case llm.extract(prompt, %{type: "array"}, max_tokens: 500) do
      {:ok, facts} when is_list(facts) ->
        # Validate and normalize the facts
        normalized =
          facts
          |> Enum.filter(fn f -> is_map(f) and Map.has_key?(f, "fact") end)
          |> Enum.map(fn f ->
            %{
              "fact" => Map.get(f, "fact", ""),
              "confidence" => Map.get(f, "confidence", 0.7) |> ensure_float()
            }
          end)

        {:ok, normalized}

      {:ok, _} ->
        {:ok, []}

      {:error, _} = error ->
        Logger.warning("Fact extraction failed: #{inspect(error)}")
        {:ok, []}
    end
  end

  defp ensure_float(val) when is_float(val), do: val
  defp ensure_float(val) when is_integer(val), do: val / 1.0
  defp ensure_float(_), do: 0.7

  @doc """
  Discovers related topics to potentially queue for research.
  """
  def discover_related_topics(content, current_topic, llm) do
    prompt = """
    Based on this content about "#{current_topic}", suggest 2-4 related topics
    that would be valuable to learn next.

    Content:
    #{String.slice(content, 0, 2000)}

    Choose topics that:
    - Are directly referenced or prerequisite knowledge
    - Would deepen understanding of #{current_topic}
    - Are specific enough to research effectively

    IMPORTANT: Return ONLY a valid JSON array of strings, nothing else. No markdown, no explanation.
    Format exactly like this: ["Topic One", "Topic Two", "Topic Three"]

    Return [] if no related topics can be identified.
    """

    case llm.extract(prompt, %{type: "array"}, max_tokens: 200) do
      {:ok, topics} when is_list(topics) ->
        # Filter to valid strings and limit
        topics =
          topics
          |> Enum.filter(&is_binary/1)
          |> Enum.map(&String.trim/1)
          |> Enum.reject(&(&1 == ""))
          |> Enum.take(4)

        {:ok, topics}

      {:ok, _} ->
        {:ok, []}

      {:error, _} = error ->
        Logger.warning("Topic discovery failed: #{inspect(error)}")
        {:ok, []}
    end
  end

  # ============================================================================
  # Utilities
  # ============================================================================

  defp estimate_tokens(content, summary, facts) do
    # Rough estimate: 4 chars per token
    content_tokens = div(String.length(content), 4)
    summary_tokens = div(String.length(summary), 4)

    facts_text =
      Enum.map_join(facts, " ", fn f -> f["fact"] || "" end)

    facts_tokens = div(String.length(facts_text), 4)

    # Input tokens (content sent to LLM)
    input = div(content_tokens, 2)
    # Output tokens (summary + facts)
    output = summary_tokens + facts_tokens + 100

    input + output
  end
end
