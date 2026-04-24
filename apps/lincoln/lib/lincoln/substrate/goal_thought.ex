defmodule Lincoln.Substrate.GoalThought do
  @moduledoc """
  Substrate-native reasoning about goals.

  When the `:goal_pursuit` impulse wins the Attention competition, the Thought
  delegates here. We pick the next pursuable goal — highest priority, stale
  evaluation — and ask the LLM what the next step is and how on-track the
  goal is. We record a reflection memory and update `progress_estimate` /
  `last_evaluated_at`. **No actions are executed in this phase**; the
  `ActionThought` arrives in Phase 5 and consumes goal recommendations.
  """

  alias Lincoln.{Goals, Memory}
  alias Lincoln.Goals.Goal

  require Logger

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

    case llm_reflection(goal) do
      {:ok, %{"progress" => progress, "next_step" => next_step}} when is_number(progress) ->
        {:ok, _} = Goals.record_progress(goal, clamp(progress, 0.0, 1.0))
        record_memory(agent, goal, progress, next_step)

        summary =
          "Goal '#{String.slice(goal.statement, 0, 60)}' — progress " <>
            "#{round(progress * 100)}%, next step: " <>
            String.slice(to_string(next_step || "none"), 0, 80)

        Logger.info("[GoalThought] #{summary}")
        {:ok, summary}

      _ ->
        # Even when extraction fails, mark the goal as evaluated so it doesn't
        # immediately re-fire the same impulse.
        {:ok, _} = Goals.record_progress(goal, goal.progress_estimate)
        {:ok, "Reflected on '#{String.slice(goal.statement, 0, 60)}' — no structured update"}
    end
  end

  defp llm_reflection(goal) do
    prompt = """
    You are reasoning about an active goal Lincoln is pursuing.

    Goal: #{goal.statement}
    Priority: #{goal.priority}/10
    Deadline: #{format_deadline(goal.deadline)}
    Current progress estimate: #{Float.round(goal.progress_estimate * 100, 0)}%

    Consider what concrete next step would advance this goal, and how
    much progress has likely been made (be honest — under-estimate when uncertain).

    Return JSON:
    {
      "progress": 0.0-1.0,
      "next_step": "A single concrete next action",
      "reasoning": "Brief justification"
    }
    """

    llm_adapter().extract(prompt, %{type: "object"}, [])
  rescue
    e ->
      Logger.warning("[GoalThought] LLM call failed: #{Exception.message(e)}")
      {:error, :llm_failed}
  end

  defp record_memory(agent, goal, progress, next_step) do
    content =
      "Goal reflection on '#{String.slice(goal.statement, 0, 100)}': " <>
        "progress #{Float.round(progress * 100, 0)}%, next step '#{String.slice(to_string(next_step || ""), 0, 200)}'"

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

  defp format_deadline(nil), do: "no deadline"
  defp format_deadline(%DateTime{} = dt), do: DateTime.to_string(dt)

  defp clamp(n, lo, hi) when is_number(n), do: n |> max(lo) |> min(hi)
  defp clamp(_, lo, _hi), do: lo

  defp llm_adapter do
    Application.get_env(:lincoln, :llm_adapter, Lincoln.Adapters.LLM.Anthropic)
  end
end
