defmodule Lincoln.Substrate.GoalThought do
  @moduledoc """
  Substrate-native reasoning about goals.

  When the `:goal_pursuit` impulse wins the Attention competition, the Thought
  delegates here. We pick the next pursuable goal — highest priority, stale
  evaluation — gather goal-relevant context (recent memories, similar
  beliefs, prior goal-reflection memories), ask the LLM to evaluate progress
  against actual evidence and propose a concrete next step, and — when the
  next step looks research-shaped — queue a high-priority Question that the
  `:investigation` impulse picks up and grounds via Tavily.

  Closing this loop is what makes goals actually advance:

      goal reflection ──▶ research question ──▶ investigation + Tavily
              ▲                                          │
              │                                          ▼
        new context next time   ◀──   finding + maybe new belief

  The first iteration of this module evaluated progress with no context at
  all — just the goal statement and the prior estimate — which made it
  impossible for the LLM to update progress meaningfully. Goals stuck at
  whatever they were initialized to. This version provides evidence and
  produces evidence.
  """

  alias Lincoln.{Beliefs, Goals, Memory, Questions}
  alias Lincoln.Goals.Goal

  require Logger

  # Priority floor for goal-derived questions. Above the curiosity-default 5
  # so the next investigation impulse picks goal questions before the meta
  # backlog. Same priority as perception-derived questions for consistency.
  @goal_question_priority 8

  @doc """
  Reason about the next pursuable goal for the agent.
  """
  def execute(agent) do
    case Goals.next_pursuable_goal(agent) do
      nil ->
        {:ok, "No active goals to pursue"}

      %Goal{} = goal ->
        reason_about(agent, goal)
    end
  end

  defp reason_about(agent, goal) do
    Logger.info("[GoalThought] Reasoning about goal #{goal.id}: #{goal.statement}")

    context = gather_context(agent, goal)

    case llm_reflection(goal, context) do
      {:ok, %{"progress" => progress, "next_step" => next_step} = data}
      when is_number(progress) ->
        clamped = clamp(progress, 0.0, 1.0)
        {:ok, _} = Goals.record_progress(goal, clamped)
        record_memory(agent, goal, clamped, next_step)
        question_id = maybe_create_question(agent, goal, data)

        summary = build_summary(goal, clamped, next_step, question_id)
        Logger.info("[GoalThought] #{summary}")
        {:ok, summary}

      _ ->
        # Even when extraction fails, mark the goal as evaluated so it doesn't
        # immediately re-fire the same impulse.
        {:ok, _} = Goals.record_progress(goal, goal.progress_estimate)
        {:ok, "Reflected on '#{String.slice(goal.statement, 0, 60)}' — no structured update"}
    end
  end

  # ---------------------------------------------------------------------------
  # Context — same shape InvestigationThought uses, scoped to this goal.
  # ---------------------------------------------------------------------------

  defp gather_context(agent, goal) do
    embedding = embed_or_nil(goal.statement)

    %{
      relevant_memories: relevant_memories(agent, embedding),
      relevant_beliefs: relevant_beliefs(agent, embedding),
      prior_goal_reflections: prior_goal_reflections(agent, goal)
    }
  end

  defp embed_or_nil(text) do
    case embeddings_adapter().embed(text, []) do
      {:ok, embedding} -> embedding
      _ -> nil
    end
  rescue
    _ -> nil
  end

  defp relevant_memories(_agent, nil), do: []

  defp relevant_memories(agent, embedding) do
    Memory.retrieve_memories(agent, embedding, limit: 5)
  rescue
    _ -> []
  end

  defp relevant_beliefs(_agent, nil), do: []

  defp relevant_beliefs(agent, embedding) do
    Beliefs.find_similar_beliefs(agent, embedding, limit: 5)
  rescue
    _ -> []
  end

  defp prior_goal_reflections(agent, goal) do
    # Pull the most recent reflection memories tagged with this goal's id so
    # the LLM sees what was tried last time and what next_step was proposed.
    Memory.list_memories_by_type(agent, "reflection", limit: 50)
    |> Enum.filter(fn m -> Map.get(m.source_context || %{}, "goal_id") == goal.id end)
    |> Enum.take(3)
  rescue
    _ -> []
  end

  # ---------------------------------------------------------------------------
  # LLM call — now grounded in context
  # ---------------------------------------------------------------------------

  defp llm_reflection(goal, context) do
    prompt = """
    You are reasoning about an active goal Lincoln is pursuing.

    Goal: #{goal.statement}
    Priority: #{goal.priority}/10
    Deadline: #{format_deadline(goal.deadline)}
    Current progress estimate: #{Float.round(goal.progress_estimate * 100, 0)}%

    EVIDENCE FROM LINCOLN'S COGNITIVE STATE:

    Relevant beliefs Lincoln currently holds:
    #{format_beliefs(context.relevant_beliefs)}

    Relevant memories (observations, prior reflections, findings):
    #{format_memories(context.relevant_memories)}

    Prior reflections on THIS goal (most recent first):
    #{format_prior_reflections(context.prior_goal_reflections)}

    Your task:

    1. Evaluate progress based on the EVIDENCE — count beliefs formed,
       investigations completed, observations integrated, prior reflections
       that show movement. Don't move progress without evidence; do move
       progress when evidence supports it. The "be honest, under-estimate"
       rule applies, but if the evidence shows real activity you can and
       should move past the prior estimate.

    2. Propose a single concrete next step. Mark it as one of:
         "research"   — needs external information; will become a question
                        that Lincoln investigates against the web
         "reflect"    — needs internal reasoning over existing beliefs
         "act"        — needs an external action (send a message, write a
                        file, etc.); not yet wired but will be in future
         "decompose"  — too big; needs to be broken into sub-goals

    Return JSON:
    {
      "progress": 0.0-1.0,
      "next_step": "A single concrete next step",
      "next_step_kind": "research|reflect|act|decompose",
      "research_question": "If next_step_kind is research, the precise question Lincoln should investigate; otherwise empty string",
      "reasoning": "Brief justification of progress estimate and next step"
    }
    """

    llm_adapter().extract(prompt, %{type: "object"}, [])
  rescue
    e ->
      Logger.warning("[GoalThought] LLM call failed: #{Exception.message(e)}")
      {:error, :llm_failed}
  end

  # ---------------------------------------------------------------------------
  # Question generation — the loop-closing piece
  # ---------------------------------------------------------------------------

  defp maybe_create_question(agent, goal, %{"next_step_kind" => "research"} = data) do
    question = research_question(data)

    if is_binary(question) and byte_size(question) > 8 do
      case Questions.ask_question(agent, question,
             priority: @goal_question_priority,
             context: "From goal: #{goal.statement}"
           ) do
        {:ok, %{id: id}} ->
          Logger.info(
            "[GoalThought] Queued research question for investigation: " <>
              String.slice(question, 0, 80)
          )

          id

        {:ok, _} ->
          nil

        _ ->
          nil
      end
    else
      nil
    end
  rescue
    e ->
      Logger.warning("[GoalThought] Question creation failed: #{Exception.message(e)}")
      nil
  end

  defp maybe_create_question(_agent, _goal, _data), do: nil

  defp research_question(%{"research_question" => q}) when is_binary(q), do: String.trim(q)
  defp research_question(_), do: ""

  # ---------------------------------------------------------------------------
  # Memory + summary
  # ---------------------------------------------------------------------------

  defp record_memory(agent, goal, progress, next_step) do
    content =
      "Goal reflection on '#{String.slice(goal.statement, 0, 100)}': " <>
        "progress #{round(progress * 100)}%, next step '" <>
        String.slice(to_string(next_step || ""), 0, 200) <> "'"

    Memory.create_memory(agent, %{
      content: content,
      memory_type: "reflection",
      importance: 6,
      source_context: %{
        "source" => "goal_thought",
        "goal_id" => goal.id,
        "progress_estimate" => progress
      }
    })
  rescue
    e ->
      Logger.warning("[GoalThought] Memory write failed: #{Exception.message(e)}")
      :ok
  end

  defp build_summary(goal, progress, next_step, question_id) do
    base =
      "Goal '#{String.slice(goal.statement, 0, 60)}' — progress " <>
        "#{round(progress * 100)}%, next step: " <>
        String.slice(to_string(next_step || "none"), 0, 80)

    if question_id, do: base <> " [queued for investigation]", else: base
  end

  # ---------------------------------------------------------------------------
  # Formatters
  # ---------------------------------------------------------------------------

  defp format_beliefs([]), do: "(none similar)"

  defp format_beliefs(beliefs) do
    Enum.map_join(beliefs, "\n", fn b ->
      stmt = Map.get(b, :statement) || b[:statement] || ""
      conf = Map.get(b, :confidence) || b[:confidence] || 0.0
      "- #{String.slice(stmt, 0, 200)} (confidence #{Float.round(conf * 1.0, 2)})"
    end)
  end

  defp format_memories([]), do: "(none similar)"

  defp format_memories(memories) do
    Enum.map_join(memories, "\n", fn m ->
      content = Map.get(m, :content) || m[:content] || ""
      type = Map.get(m, :memory_type) || m[:memory_type] || "memory"
      "- [#{type}] #{String.slice(content, 0, 200)}"
    end)
  end

  defp format_prior_reflections([]), do: "(none yet — this is the first reflection on this goal)"

  defp format_prior_reflections(reflections) do
    Enum.map_join(reflections, "\n", fn m ->
      "- #{String.slice(m.content || "", 0, 200)}"
    end)
  end

  defp format_deadline(nil), do: "no deadline"
  defp format_deadline(%DateTime{} = dt), do: DateTime.to_string(dt)

  defp clamp(n, lo, hi) when is_number(n), do: n |> max(lo) |> min(hi)
  defp clamp(_, lo, _hi), do: lo

  defp llm_adapter do
    Application.get_env(:lincoln, :llm_adapter, Lincoln.Adapters.LLM.Anthropic)
  end

  defp embeddings_adapter do
    Application.get_env(:lincoln, :embeddings_adapter, Lincoln.Adapters.Embeddings.PythonService)
  end
end
