defmodule Lincoln.Substrate.PerceptionThought do
  @moduledoc """
  Substrate-native processing of unprocessed observation memories.

  When the `:perception` impulse wins the Attention competition, the Thought
  process delegates here. We pick the highest-importance unprocessed observation
  from the last 24h, ask the LLM whether it carries an extractable claim, and
  — if confidence is high enough — form a belief from it.

  The observation is always marked `processed_at` afterwards, even if no belief
  is formed. That keeps the perception impulse from oscillating on the same
  observation forever.
  """

  alias Lincoln.{Cognition, Memory, Questions}

  require Logger

  @belief_confidence_threshold 0.7
  # Priority for follow-up questions generated from observations that lacked
  # an extractable claim. Above the priority-5 default of curiosity-generated
  # questions so investigation picks them up first — the path that wires
  # external observations into the Tavily search pipeline.
  @perception_question_priority 8

  @doc """
  Process the next unprocessed observation for the agent.

  Returns `{:ok, summary}` or `{:ok, "Nothing to perceive"}`.
  """
  def execute(agent) do
    case Memory.list_unprocessed_observations(agent, hours: 24, limit: 1) do
      [] ->
        {:ok, "No unprocessed observations"}

      [memory | _] ->
        process(agent, memory)
    end
  end

  defp process(agent, memory) do
    Logger.info(
      "[PerceptionThought] Processing observation #{memory.id} from #{source_label(memory)}"
    )

    case extract_claim(memory) do
      {:ok, %{"claim" => "", "confidence" => _} = data} ->
        # Empty claim, but the observation may still raise a useful question.
        # When it does, queue the question — the :investigation impulse picks
        # the highest-priority open question every minute and runs it through
        # Tavily, so this is the perception → question → search path.
        question_id = maybe_create_question(agent, memory, data)
        {:ok, _} = Memory.mark_processed(memory, [])

        summary =
          if question_id,
            do:
              "Observation noted; asked '" <>
                String.slice(question_text(data), 0, 80) <> "' for investigation",
            else: "Observation noted but no extractable claim or question"

        Logger.info("[PerceptionThought] #{summary}")
        {:ok, summary}

      {:ok, %{"claim" => claim, "confidence" => confidence} = data}
      when is_binary(claim) and is_number(confidence) ->
        belief_id = maybe_form_belief(agent, memory, claim, confidence, data)
        # Even when a claim is extracted, a follow-up question often points
        # somewhere external the belief alone doesn't reach. Queue it too.
        _question_id = maybe_create_question(agent, memory, data)
        {:ok, _} = Memory.mark_processed(memory, belief_id: belief_id)

        summary =
          "Perceived '#{String.slice(memory.content, 0, 50)}' → " <>
            describe_outcome(belief_id, claim, confidence)

        Logger.info("[PerceptionThought] #{summary}")
        {:ok, summary}

      _ ->
        {:ok, _} = Memory.mark_processed(memory, [])
        {:ok, "Observation noted but no extractable claim"}
    end
  end

  defp extract_claim(memory) do
    prompt = """
    You are reviewing an observation Lincoln received from the outside world.
    Decide whether it contains a claim worth adding to Lincoln's belief
    system, AND whether it raises an outward-looking question Lincoln should
    investigate.

    Observation source: #{source_label(memory)}
    Observation content:
    #{memory.content}

    Two extractions, both optional:

    1. CLAIM — a single, well-formed declarative statement that could be a
       belief Lincoln holds about the world. If the observation is purely
       informational, ambiguous, or merely an event, return claim: "".

    2. FOLLOW_UP_QUESTION — an outward-looking question this observation
       raises that Lincoln should research. Prefer questions that point
       beyond Lincoln's current Elixir/BEAM/identity introspection toward
       the topic the observation is about. Empty string if nothing useful.

    Return JSON:
    {
      "claim": "...",
      "confidence": 0.0-1.0,
      "follow_up_question": "What this observation makes Lincoln want to know about the world, or empty string",
      "reasoning": "Brief justification"
    }
    """

    llm_adapter().extract(prompt, %{type: "object"}, [])
  rescue
    e ->
      Logger.warning("[PerceptionThought] LLM call failed: #{Exception.message(e)}")
      {:error, :llm_failed}
  end

  defp maybe_form_belief(_agent, _memory, "", _confidence, _data), do: nil

  defp maybe_form_belief(agent, memory, claim, confidence, _data)
       when confidence >= @belief_confidence_threshold do
    case Cognition.form_belief(agent, claim, "observation",
           confidence: confidence,
           evidence:
             "Perceived from #{source_label(memory)}: #{String.slice(memory.content, 0, 200)}"
         ) do
      {:ok, belief} -> belief.id
      _ -> nil
    end
  rescue
    e ->
      Logger.warning("[PerceptionThought] Belief formation failed: #{Exception.message(e)}")
      nil
  end

  defp maybe_form_belief(_agent, _memory, _claim, _confidence, _data), do: nil

  defp maybe_create_question(agent, memory, data) do
    case question_text(data) do
      "" ->
        nil

      text when is_binary(text) and byte_size(text) > 8 ->
        case Questions.ask_question(agent, text,
               priority: @perception_question_priority,
               context: "Raised by observation from #{source_label(memory)}"
             ) do
          {:ok, %{id: id}} ->
            Logger.info(
              "[PerceptionThought] Queued question for investigation: #{String.slice(text, 0, 80)}"
            )

            id

          {:ok, _} ->
            nil

          _ ->
            nil
        end

      _ ->
        nil
    end
  rescue
    e ->
      Logger.warning("[PerceptionThought] Question creation failed: #{Exception.message(e)}")
      nil
  end

  defp question_text(%{"follow_up_question" => q}) when is_binary(q), do: String.trim(q)
  defp question_text(_), do: ""

  defp describe_outcome(nil, _claim, confidence) do
    "claim too uncertain (#{Float.round(confidence * 100, 0)}%)"
  end

  defp describe_outcome(_belief_id, claim, confidence) do
    "formed belief '#{String.slice(claim, 0, 60)}' (#{Float.round(confidence * 100, 0)}%)"
  end

  defp source_label(%{source_context: %{"source" => s}}) when is_binary(s), do: s
  defp source_label(_), do: "unknown source"

  defp llm_adapter do
    Application.get_env(:lincoln, :llm_adapter, Lincoln.Adapters.LLM.Anthropic)
  end
end
