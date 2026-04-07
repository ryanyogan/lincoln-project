# Lincoln's Cognitive Thought Loop
# Enables iterative deliberation before responding
# Integrates with Lincoln's self-written BeliefFormation module

defmodule Lincoln.Cognition.ThoughtLoop do
  @moduledoc """
  Iterative deliberation loop for Lincoln's responses.

  Enables Lincoln to:
  - Draft a response
  - Evaluate it against his beliefs and confidence
  - Revise if uncertainty is high or inconsistencies detected
  - Finalize with a thinking trace
  - Optionally give up and acknowledge uncertainty

  Integrates Lincoln's self-written BeliefFormation module for metacognitive
  assessment of response quality.

  ## The Loop

  ```
  DRAFT → EVALUATE → RECONSIDER (if needed) → FINALIZE
            ↑           ↓
            └───────────┘
  ```

  ## Configuration

  - Max iterations: 3 (to prevent infinite loops)
  - Confidence threshold: 0.6 (below this triggers reconsideration)
  - Can "give up" and acknowledge uncertainty if unable to reach confidence
  """

  require Logger

  alias Lincoln.Events.{AdaptiveThresholds, Emitter}
  alias Lincoln.Learning.BeliefFormation

  @max_iterations 3
  @confidence_threshold 0.6
  @consistency_threshold 0.7

  defstruct [
    :draft,
    :evaluation,
    :iteration,
    :final_response,
    :thinking_trace,
    :gave_up,
    :confidence_score
  ]

  @type t :: %__MODULE__{
          draft: String.t() | nil,
          evaluation: map() | nil,
          iteration: non_neg_integer(),
          final_response: String.t() | nil,
          thinking_trace: list(),
          gave_up: boolean(),
          confidence_score: float()
        }

  @doc """
  Run the thought loop on a cognitive state.

  Takes the state from the REASON step and iteratively refines the response
  before passing to RESPOND.

  Returns updated state with:
  - Additional context for response generation
  - Thinking trace in cognitive_metadata
  - Confidence assessment
  """
  def deliberate(state, opts \\ []) do
    llm = Keyword.get(opts, :llm, get_llm_adapter())
    start_time = System.monotonic_time(:millisecond)

    loop_state = %__MODULE__{
      iteration: 0,
      thinking_trace: [],
      gave_up: false,
      confidence_score: 0.0
    }

    # Get metacognitive profile from Lincoln's self-written module
    confidence_profile = get_confidence_profile()

    # Run the deliberation loop
    case run_loop(state, loop_state, confidence_profile, llm) do
      {:ok, final_loop_state} ->
        duration_ms = System.monotonic_time(:millisecond) - start_time

        # Emit events for self-awareness
        emit_deliberation_events(state.agent, final_loop_state, duration_ms, state.user_message)

        # Update cognitive state with deliberation results
        updated_metadata =
          state.cognitive_metadata
          |> Map.put(:thought_iterations, final_loop_state.iteration)
          |> Map.put(:deliberation_trace, final_loop_state.thinking_trace)
          |> Map.put(:deliberation_confidence, final_loop_state.confidence_score)
          |> Map.put(:gave_up, final_loop_state.gave_up)

        updated_state =
          %{state | cognitive_metadata: updated_metadata}
          |> maybe_add_uncertainty_context(final_loop_state)

        {:ok, updated_state}

      {:error, reason} ->
        Logger.warning("ThoughtLoop failed: #{inspect(reason)}, proceeding without deliberation")
        {:ok, state}
    end
  end

  # Emit events based on deliberation outcome
  defp emit_deliberation_events(agent, loop_state, duration_ms, user_message) do
    # Emit if gave up
    if loop_state.gave_up do
      Emitter.emit(agent, :thought_loop_gave_up, %{
        duration_ms: duration_ms,
        iterations: loop_state.iteration,
        final_confidence: loop_state.confidence_score,
        related_topic: extract_topic(user_message),
        context: %{
          message_preview: String.slice(user_message, 0, 100)
        }
      })
    end

    # Emit if slow (check against adaptive threshold)
    if AdaptiveThresholds.slow?(agent, "thought_loop", duration_ms) do
      Emitter.emit(agent, :thought_loop_slow, %{
        duration_ms: duration_ms,
        iterations: loop_state.iteration,
        related_topic: extract_topic(user_message)
      })
    end

    # Emit low confidence even if didn't give up
    if loop_state.confidence_score < @confidence_threshold and not loop_state.gave_up do
      Emitter.emit(agent, :low_confidence_response, %{
        confidence: loop_state.confidence_score,
        iterations: loop_state.iteration,
        related_topic: extract_topic(user_message)
      })
    end
  end

  defp extract_topic(message) do
    # Simple topic extraction - take first few words
    message
    |> String.split()
    |> Enum.take(5)
    |> Enum.join(" ")
  end

  # ============================================================================
  # Loop Execution
  # ============================================================================

  defp run_loop(state, loop_state, confidence_profile, llm) do
    if loop_state.iteration >= @max_iterations do
      # Max iterations reached - either finalize or give up
      if loop_state.confidence_score < @confidence_threshold do
        {:ok,
         %{
           loop_state
           | gave_up: true,
             thinking_trace:
               add_trace(
                 loop_state,
                 "Reached max iterations without sufficient confidence - acknowledging uncertainty"
               )
         }}
      else
        {:ok, loop_state}
      end
    else
      # Step 1: Draft (or get existing draft)
      loop_state =
        if loop_state.draft == nil do
          draft_response(state, loop_state, llm)
        else
          loop_state
        end

      # Step 2: Evaluate
      loop_state = evaluate_draft(state, loop_state, confidence_profile)

      # Step 3: Decide whether to continue
      cond do
        loop_state.confidence_score >= @confidence_threshold ->
          # Good enough - finalize
          {:ok,
           %{
             loop_state
             | final_response: loop_state.draft,
               thinking_trace:
                 add_trace(
                   loop_state,
                   "Confidence #{Float.round(loop_state.confidence_score, 2)} meets threshold - finalizing"
                 )
           }}

        should_give_up?(loop_state) ->
          # Unable to improve - acknowledge uncertainty
          {:ok,
           %{
             loop_state
             | gave_up: true,
               final_response: loop_state.draft,
               thinking_trace:
                 add_trace(
                   loop_state,
                   "Unable to reach confidence threshold - will acknowledge uncertainty"
                 )
           }}

        true ->
          # Reconsider and iterate
          loop_state = reconsider(state, loop_state, llm)
          run_loop(state, loop_state, confidence_profile, llm)
      end
    end
  end

  # ============================================================================
  # Draft Generation
  # ============================================================================

  defp draft_response(state, loop_state, llm) do
    # Generate initial draft using simplified prompt
    draft_prompt = build_draft_prompt(state, loop_state)

    case llm.complete(draft_prompt, max_tokens: 500) do
      {:ok, draft} ->
        %{
          loop_state
          | draft: draft,
            iteration: loop_state.iteration + 1,
            thinking_trace: add_trace(loop_state, "Generated initial draft")
        }

      {:error, _reason} ->
        # Fall back to no draft - will use standard response
        %{
          loop_state
          | draft: nil,
            thinking_trace:
              add_trace(loop_state, "Draft generation failed - using standard response")
        }
    end
  end

  defp build_draft_prompt(state, _loop_state) do
    """
    You are Lincoln, thinking through how to respond to this message.

    User message: #{state.user_message}

    Your relevant memories: #{format_memories(state.context.memories)}
    Your relevant beliefs: #{format_beliefs(state.context.beliefs)}

    Generate a response draft. Be natural and conversational.
    Consider your beliefs and memories when forming your response.
    """
  end

  # ============================================================================
  # Evaluation
  # ============================================================================

  defp evaluate_draft(state, loop_state, confidence_profile) do
    # Evaluate the draft against beliefs and confidence

    # Check belief consistency
    consistency_score = evaluate_belief_consistency(loop_state.draft, state.context.beliefs)

    # Get metacognitive assessment
    metacognitive_score = get_metacognitive_score(confidence_profile)

    # Check if draft addresses the message appropriately
    relevance_score = evaluate_relevance(loop_state.draft, state.user_message)

    # Combined confidence score
    confidence = consistency_score * 0.4 + metacognitive_score * 0.3 + relevance_score * 0.3

    evaluation = %{
      consistency: consistency_score,
      metacognitive: metacognitive_score,
      relevance: relevance_score,
      issues: identify_issues(consistency_score, metacognitive_score, relevance_score)
    }

    %{
      loop_state
      | evaluation: evaluation,
        confidence_score: confidence,
        thinking_trace:
          add_trace(
            loop_state,
            "Evaluated draft: confidence=#{Float.round(confidence, 2)}, issues=#{inspect(evaluation.issues)}"
          )
    }
  end

  defp evaluate_belief_consistency(nil, _beliefs), do: 0.5
  # No beliefs to contradict
  defp evaluate_belief_consistency(_draft, []), do: 0.7

  defp evaluate_belief_consistency(draft, beliefs) do
    # Simple heuristic: check if draft mentions topics from beliefs
    draft_lower = String.downcase(draft)

    relevant_beliefs =
      Enum.filter(beliefs, fn belief ->
        belief_words = belief.statement |> String.downcase() |> String.split()

        Enum.any?(belief_words, fn word ->
          String.length(word) > 4 and String.contains?(draft_lower, word)
        end)
      end)

    if Enum.empty?(relevant_beliefs) do
      # No relevant beliefs found - neutral
      0.6
    else
      # Higher score if we have beliefs and mention them
      min(0.9, 0.6 + length(relevant_beliefs) * 0.1)
    end
  end

  defp get_metacognitive_score(nil), do: 0.5

  defp get_metacognitive_score(profile) do
    profile.uncertainty_adjusted_confidence || 0.5
  end

  defp evaluate_relevance(nil, _message), do: 0.3

  defp evaluate_relevance(draft, message) do
    # Simple heuristic: check word overlap
    message_words = message |> String.downcase() |> String.split() |> MapSet.new()
    draft_words = draft |> String.downcase() |> String.split() |> MapSet.new()

    overlap = MapSet.intersection(message_words, draft_words) |> MapSet.size()
    message_size = MapSet.size(message_words)

    if message_size == 0 do
      0.5
    else
      # Scale up since partial overlap is expected
      min(1.0, overlap / message_size * 2)
    end
  end

  defp identify_issues(consistency, metacognitive, relevance) do
    issues = []

    issues =
      if consistency < @consistency_threshold, do: [:low_consistency | issues], else: issues

    issues = if metacognitive < 0.5, do: [:high_uncertainty | issues], else: issues
    issues = if relevance < 0.5, do: [:low_relevance | issues], else: issues
    issues
  end

  # ============================================================================
  # Reconsideration
  # ============================================================================

  defp reconsider(state, loop_state, llm) do
    issues = loop_state.evaluation.issues || []

    # Build reconsideration prompt based on issues
    reconsider_prompt = build_reconsider_prompt(state, loop_state, issues)

    case llm.complete(reconsider_prompt, max_tokens: 500) do
      {:ok, revised_draft} ->
        %{
          loop_state
          | draft: revised_draft,
            iteration: loop_state.iteration + 1,
            thinking_trace:
              add_trace(loop_state, "Reconsidered draft addressing: #{inspect(issues)}")
        }

      {:error, _reason} ->
        # Keep existing draft
        %{
          loop_state
          | iteration: loop_state.iteration + 1,
            thinking_trace:
              add_trace(loop_state, "Reconsideration failed - keeping existing draft")
        }
    end
  end

  defp build_reconsider_prompt(state, loop_state, issues) do
    issue_guidance =
      Enum.map_join(issues, "\n", fn
        :low_consistency -> "- Ensure your response aligns with your beliefs"
        :high_uncertainty -> "- Acknowledge uncertainty where appropriate"
        :low_relevance -> "- Make sure you directly address the user's message"
      end)

    """
    You are Lincoln, revising your response draft.

    User message: #{state.user_message}

    Your previous draft: #{loop_state.draft}

    Issues to address:
    #{issue_guidance}

    Your beliefs: #{format_beliefs(state.context.beliefs)}

    Generate an improved response that addresses these issues.
    """
  end

  defp should_give_up?(loop_state) do
    # Give up if we've iterated multiple times with no improvement
    loop_state.iteration >= 2 and loop_state.confidence_score < 0.4
  end

  # ============================================================================
  # Helpers
  # ============================================================================

  defp maybe_add_uncertainty_context(state, %{gave_up: true}) do
    # Add context to help Lincoln acknowledge uncertainty in response
    uncertainty_note = """

    Note: You're uncertain about this response. Consider:
    - Acknowledging what you don't know
    - Suggesting the user verify important claims
    - Expressing your reasoning process
    """

    updated_context = Map.put(state.context, :uncertainty_guidance, uncertainty_note)
    %{state | context: updated_context}
  end

  defp maybe_add_uncertainty_context(state, _loop_state), do: state

  defp get_confidence_profile do
    BeliefFormation.start_confidence_tracking()
    BeliefFormation.get_decision_making_confidence_profile()
  rescue
    _ -> %{uncertainty_adjusted_confidence: 0.5, decision_reliability: :unknown}
  end

  defp add_trace(loop_state, message) do
    entry = %{
      iteration: loop_state.iteration,
      timestamp: DateTime.utc_now() |> DateTime.truncate(:second),
      message: message
    }

    [entry | loop_state.thinking_trace]
  end

  defp format_memories([]), do: "None"

  defp format_memories(memories) do
    memories
    |> Enum.take(3)
    |> Enum.map_join("\n", fn m -> "- #{truncate(m.content, 100)}" end)
  end

  defp format_beliefs([]), do: "None"

  defp format_beliefs(beliefs) do
    beliefs
    |> Enum.take(3)
    |> Enum.map_join("\n", fn b ->
      "- #{truncate(b.statement, 80)} (#{round(b.confidence * 100)}% confident)"
    end)
  end

  defp truncate(str, len) when is_binary(str) do
    if String.length(str) > len do
      String.slice(str, 0, len) <> "..."
    else
      str
    end
  end

  defp truncate(_, _), do: ""

  defp get_llm_adapter do
    Application.get_env(:lincoln, :llm_adapter, Lincoln.Adapters.LLM.Anthropic)
  end
end
