defmodule Lincoln.Substrate.GoalReviewThought do
  @moduledoc """
  Periodic review of all active goals for relevance.

  Fires via the `:goal_review` impulse (hourly). Evaluates whether goals
  should be abandoned, reprioritized, or are now irrelevant given new
  beliefs. GoalThought evaluates *progress*; GoalReviewThought evaluates
  *relevance*.
  """

  alias Lincoln.{Beliefs, Goals, Memory}

  require Logger

  @doc """
  Review all active goals for the given agent and recommend changes.
  """
  def execute(agent) do
    goals = Goals.list_goals(agent, status: "active")

    if goals == [] do
      {:ok, "No active goals to review"}
    else
      review_all(agent, goals)
    end
  end

  defp review_all(agent, goals) do
    # Gather recent beliefs as context for relevance evaluation
    recent_beliefs = Beliefs.list_beliefs(agent, status: "active", limit: 20)

    case llm_review(goals, recent_beliefs) do
      {:ok, recommendations} ->
        changes = apply_recommendations(goals, recommendations)
        record_review_memory(agent, goals, changes)
        summary = build_summary(changes)
        Logger.info("[GoalReviewThought] #{summary}")
        {:ok, summary}

      {:error, reason} ->
        Logger.warning("[GoalReviewThought] Review failed: #{inspect(reason)}")
        {:ok, "Goal review attempted but LLM evaluation failed"}
    end
  end

  # ---------------------------------------------------------------------------
  # LLM evaluation
  # ---------------------------------------------------------------------------

  defp llm_review(goals, beliefs) do
    goals_text = format_goals(goals)
    beliefs_text = format_beliefs(beliefs)

    prompt = """
    You are reviewing Lincoln's active goals to determine if any should be abandoned,
    reprioritized, or are now irrelevant.

    Active Goals:
    #{goals_text}

    Current Beliefs (most relevant context):
    #{beliefs_text}

    For each goal, evaluate:
    1. Is this goal still relevant given current beliefs and context?
    2. Should the priority be changed?
    3. Should this goal be abandoned?

    Return JSON array:
    [
      {
        "goal_index": 0,
        "action": "keep" | "reprioritize" | "abandon",
        "new_priority": 1-10 (only if action is "reprioritize"),
        "reason": "Brief explanation"
      }
    ]
    """

    llm_adapter().extract(prompt, %{type: "array"}, [])
  rescue
    e ->
      Logger.warning("[GoalReviewThought] LLM call failed: #{Exception.message(e)}")
      {:error, :llm_failed}
  end

  # ---------------------------------------------------------------------------
  # Applying recommendations
  # ---------------------------------------------------------------------------

  defp apply_recommendations(goals, recommendations) when is_list(recommendations) do
    Enum.reduce(recommendations, [], fn rec, acc ->
      index = Map.get(rec, "goal_index")
      action = Map.get(rec, "action")
      goal = Enum.at(goals, index || -1)

      if goal do
        case apply_single(goal, action, rec) do
          {:ok, change} -> [change | acc]
          :skip -> acc
        end
      else
        acc
      end
    end)
  end

  defp apply_recommendations(_goals, _), do: []

  defp apply_single(goal, "abandon", rec) do
    reason = Map.get(rec, "reason", "no reason given")

    case Goals.update_status(goal, "abandoned") do
      {:ok, _} -> {:ok, {:abandoned, goal, reason}}
      _ -> :skip
    end
  end

  defp apply_single(goal, "reprioritize", rec) do
    new_priority = Map.get(rec, "new_priority", goal.priority)
    reason = Map.get(rec, "reason", "no reason given")

    case Goals.update_goal(goal, %{priority: new_priority}) do
      {:ok, _} -> {:ok, {:reprioritized, goal, new_priority, reason}}
      _ -> :skip
    end
  end

  defp apply_single(_goal, _action, _rec), do: :skip

  # ---------------------------------------------------------------------------
  # Memory + summary
  # ---------------------------------------------------------------------------

  defp record_review_memory(agent, goals, changes) do
    content =
      "Goal review of #{length(goals)} active goals: " <>
        if changes == [] do
          "all goals remain relevant"
        else
          Enum.map_join(changes, "; ", fn
            {:abandoned, g, reason} ->
              "abandoned '#{String.slice(g.statement, 0, 60)}' (#{reason})"

            {:reprioritized, g, p, _reason} ->
              "reprioritized '#{String.slice(g.statement, 0, 60)}' to P#{p}"
          end)
        end

    Memory.create_memory(agent, %{
      content: content,
      memory_type: "reflection",
      importance: 5,
      source_context: %{"source" => "goal_review"}
    })
  rescue
    _ -> :ok
  end

  defp build_summary(changes) do
    if changes == [] do
      "All active goals remain relevant"
    else
      abandoned = Enum.count(changes, &match?({:abandoned, _, _}, &1))
      reprioritized = Enum.count(changes, &match?({:reprioritized, _, _, _}, &1))

      parts =
        []
        |> then(fn acc -> if abandoned > 0, do: ["#{abandoned} abandoned" | acc], else: acc end)
        |> then(fn acc ->
          if reprioritized > 0, do: ["#{reprioritized} reprioritized" | acc], else: acc
        end)

      "Reviewed goals: #{Enum.join(parts, ", ")}"
    end
  end

  # ---------------------------------------------------------------------------
  # Formatters
  # ---------------------------------------------------------------------------

  defp format_goals(goals) do
    goals
    |> Enum.with_index()
    |> Enum.map_join("\n", fn {g, i} ->
      progress = round((g.progress_estimate || 0.0) * 100)

      age_days =
        if g.inserted_at,
          do: div(DateTime.diff(DateTime.utc_now(), g.inserted_at, :second), 86400),
          else: 0

      "#{i}. [P#{g.priority} | #{progress}% | #{age_days}d old] #{g.statement}"
    end)
  end

  defp format_beliefs(beliefs) do
    Enum.map_join(beliefs, "\n", fn b ->
      conf = Float.round((b.confidence || 0.0) * 1.0, 2)
      "- [c=#{conf}] #{String.slice(b.statement || "", 0, 200)}"
    end)
  end

  defp llm_adapter do
    Application.get_env(:lincoln, :llm_adapter, Lincoln.Adapters.LLM.Anthropic)
  end
end
