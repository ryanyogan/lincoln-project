defmodule Lincoln.Cognition.Perception do
  @moduledoc """
  Message classification and contradiction detection.

  Analyzes incoming messages to determine:
  - Message type (statement, correction, question, etc.)
  - Whether it contradicts existing beliefs
  - Facts/claims that can be extracted
  - Correction strength for belief revision decisions

  This module is critical for AGI-relevant learning:
  it helps Lincoln distinguish between different types of input
  and identify when its beliefs should be revised.
  """

  alias Lincoln.Beliefs

  # Message types (for reference):
  # :greeting, :statement, :correction, :question, :request,
  # :observation, :opinion, :emotional, :meta

  defstruct [
    :message,
    :message_type,
    :facts_claimed,
    :correction_target,
    :correction_strength,
    :emotional_tone,
    :requires_belief_check
  ]

  @doc """
  Classifies an incoming message and extracts relevant information.

  Uses pattern matching and heuristics for fast classification,
  with optional LLM fallback for ambiguous cases.

  Returns a Perception struct with classification results.
  """
  def classify_message(content) when is_binary(content) do
    content_lower = String.downcase(content)

    message_type = detect_message_type(content_lower)
    correction_indicators = detect_correction_indicators(content_lower)
    facts = extract_simple_facts(content)

    %__MODULE__{
      message: content,
      message_type: message_type,
      facts_claimed: facts,
      correction_target: nil,
      correction_strength:
        if(correction_indicators != [], do: assess_strength(correction_indicators), else: nil),
      emotional_tone: detect_emotional_tone(content_lower),
      requires_belief_check: message_type in [:statement, :correction, :observation]
    }
  end

  @doc """
  Detects if message contradicts any existing beliefs.

  Returns a list of potentially contradicted beliefs with analysis.
  Uses semantic similarity to find related beliefs, then checks for contradiction.
  """
  def detect_contradictions(content, agent_id, opts \\ []) do
    # Get embeddings adapter
    embeddings = Keyword.get(opts, :embeddings, Lincoln.Adapters.Embeddings.PythonService)

    case embeddings.embed(content, []) do
      {:ok, embedding} ->
        # Find semantically similar beliefs
        agent = Lincoln.Agents.get_agent!(agent_id)

        similar_beliefs =
          Beliefs.find_similar_beliefs(agent, embedding, limit: 5, min_similarity: 0.5)

        # For each similar belief, check if the message contradicts it
        contradictions =
          similar_beliefs
          |> Enum.map(fn belief ->
            contradiction_type = check_contradiction_type(content, belief.statement)
            %{belief: belief, contradiction_type: contradiction_type}
          end)
          |> Enum.filter(fn %{contradiction_type: type} -> type != :none end)

        {:ok, contradictions}

      {:error, reason} ->
        # Fall back to no contradiction detection if embeddings fail
        {:error, reason}
    end
  end

  @doc """
  Assesses how strong a correction is based on language used.

  - :weak - "I think", "maybe", uncertain language
  - :moderate - Direct statement without strong evidence
  - :strong - "I saw", "I verified", direct observation claims
  """
  def assess_correction_strength(message, _contradicted_belief) do
    indicators = detect_correction_indicators(String.downcase(message))
    assess_strength(indicators)
  end

  # ============================================================================
  # Private Functions
  # ============================================================================

  defp detect_message_type(content) do
    detect_type(content, [
      {:greeting, &greeting?/1},
      {:question, &question?/1},
      {:correction, &correction?/1},
      {:observation, &observation?/1},
      {:request, &request?/1},
      {:opinion, &opinion?/1},
      {:emotional, &emotional?/1},
      {:meta, &meta?/1}
    ])
  end

  defp detect_type(_content, []), do: :statement

  defp detect_type(content, [{type, check} | rest]) do
    if check.(content), do: type, else: detect_type(content, rest)
  end

  defp greeting?(content) do
    greetings =
      ~w(hello hi hey greetings howdy sup what's\ up good\ morning good\ afternoon good\ evening)

    Enum.any?(greetings, &String.starts_with?(content, &1))
  end

  @question_prefixes ~w(what how why when where who)
  @question_phrases ["can you ", "could you ", "do you "]

  defp question?(content) do
    String.ends_with?(content, "?") or
      Enum.any?(@question_prefixes, &String.starts_with?(content, &1 <> " ")) or
      Enum.any?(@question_phrases, &String.starts_with?(content, &1))
  end

  defp correction?(content) do
    correction_phrases = [
      "actually",
      "no,",
      "that's not",
      "that isn't",
      "you're wrong",
      "incorrect",
      "not quite",
      "not exactly",
      "i disagree",
      "that's incorrect",
      "you said",
      "but actually"
    ]

    Enum.any?(correction_phrases, &String.contains?(content, &1))
  end

  defp observation?(content) do
    observation_phrases = [
      "i saw",
      "i noticed",
      "i observed",
      "i just saw",
      "i witnessed",
      "i can see",
      "looking at",
      "i found",
      "i discovered"
    ]

    Enum.any?(observation_phrases, &String.contains?(content, &1))
  end

  defp request?(content) do
    request_phrases = [
      "please",
      "can you",
      "could you",
      "would you",
      "i need",
      "i want",
      "help me",
      "show me",
      "tell me",
      "explain"
    ]

    Enum.any?(request_phrases, &String.contains?(content, &1))
  end

  defp opinion?(content) do
    opinion_phrases = [
      "i think",
      "i believe",
      "in my opinion",
      "i feel",
      "it seems",
      "i'd say",
      "personally"
    ]

    Enum.any?(opinion_phrases, &String.contains?(content, &1))
  end

  defp emotional?(content) do
    emotional_phrases = [
      "i'm happy",
      "i'm sad",
      "i'm angry",
      "i'm frustrated",
      "i'm excited",
      "i love",
      "i hate",
      "i'm worried",
      "i'm anxious"
    ]

    Enum.any?(emotional_phrases, &String.contains?(content, &1))
  end

  defp meta?(content) do
    meta_phrases = [
      "do you remember",
      "what did i",
      "our last conversation",
      "earlier you said",
      "you mentioned",
      "what do you know about",
      "what are your beliefs"
    ]

    Enum.any?(meta_phrases, &String.contains?(content, &1))
  end

  defp detect_correction_indicators(content) do
    indicators = []

    # Strong correction indicators (observation-based)
    strong_indicators = [
      "i saw",
      "i verified",
      "i checked",
      "i confirmed",
      "i know for a fact",
      "i was there",
      "i witnessed"
    ]

    indicators =
      if Enum.any?(strong_indicators, &String.contains?(content, &1)) do
        [:strong_evidence | indicators]
      else
        indicators
      end

    # Direct contradiction indicators
    direct_indicators = [
      "actually",
      "no,",
      "that's wrong",
      "incorrect",
      "you're wrong"
    ]

    indicators =
      if Enum.any?(direct_indicators, &String.contains?(content, &1)) do
        [:direct_contradiction | indicators]
      else
        indicators
      end

    # Uncertainty indicators (weaken the correction)
    uncertainty_indicators = [
      "i think",
      "maybe",
      "perhaps",
      "i believe",
      "i'm not sure but",
      "possibly"
    ]

    indicators =
      if Enum.any?(uncertainty_indicators, &String.contains?(content, &1)) do
        [:uncertain | indicators]
      else
        indicators
      end

    indicators
  end

  defp assess_strength(indicators) do
    cond do
      :strong_evidence in indicators -> :strong
      :uncertain in indicators -> :weak
      :direct_contradiction in indicators -> :moderate
      indicators == [] -> nil
      true -> :moderate
    end
  end

  defp detect_emotional_tone(content) do
    cond do
      String.contains?(content, ["!", "excited", "happy", "great", "awesome"]) -> :positive
      String.contains?(content, ["sad", "angry", "frustrated", "upset", "hate"]) -> :negative
      true -> :neutral
    end
  end

  defp extract_simple_facts(content) do
    # Simple fact extraction - looks for declarative statements
    # This is a simplified version; could use LLM for more sophisticated extraction

    # Split into sentences
    sentences =
      content
      |> String.split(~r/[.!?]/)
      |> Enum.map(&String.trim/1)
      |> Enum.reject(&(&1 == ""))

    # Filter to likely factual statements (not questions, not pure opinions)
    sentences
    |> Enum.filter(fn sentence ->
      sentence_lower = String.downcase(sentence)

      # Not a question
      # Not purely emotional
      # Contains some substance (more than 3 words)
      not String.ends_with?(sentence, "?") and
        not emotional?(sentence_lower) and
        length(String.split(sentence)) > 3
    end)
    |> Enum.map(fn sentence ->
      %{
        statement: sentence,
        confidence: 0.6
      }
    end)
  end

  defp check_contradiction_type(message, belief_statement) do
    message_lower = String.downcase(message)
    belief_lower = String.downcase(belief_statement)

    # Simple heuristic: if message contains negation of key terms in belief
    negation_patterns = ["not ", "isn't ", "aren't ", "wasn't ", "weren't ", "no ", "never "]

    # Check if message appears to negate something in the belief
    has_negation = Enum.any?(negation_patterns, &String.contains?(message_lower, &1))

    # Check for shared key terms (simple word overlap)
    message_words = message_lower |> String.split() |> MapSet.new()
    belief_words = belief_lower |> String.split() |> MapSet.new()
    common_words = MapSet.intersection(message_words, belief_words)

    # Filter out common stop words
    stop_words =
      MapSet.new(
        ~w(the a an is are was were be been being have has had do does did will would could should can may might must shall)
      )

    meaningful_common = MapSet.difference(common_words, stop_words)

    cond do
      MapSet.size(meaningful_common) == 0 ->
        :none

      has_negation and MapSet.size(meaningful_common) >= 2 ->
        :direct

      MapSet.size(meaningful_common) >= 3 ->
        :potential

      true ->
        :none
    end
  end
end
