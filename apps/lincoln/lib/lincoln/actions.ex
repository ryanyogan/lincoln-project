defmodule Lincoln.Actions do
  @moduledoc """
  Lincoln's effectors — calling external tools and observing the result.

  This module owns the action lifecycle: propose → execute → observe →
  calibrate. Actions are persisted before execution so the substrate can
  reason about pending work, an audit trail exists, and calibration has
  the predicted-vs-actual diff to learn from.

  Phase 5 scope:

    * Tier 0–1 actions execute autonomously when an `:action` impulse fires.
    * Tier 2 actions are accepted but parked at `"pending_approval"` until
      Phase 7 wires the approval flow.
    * Tier 3 actions are accepted but never executed in this phase.

  Calibration writes a new belief for each executed action — observed from
  the prediction-vs-outcome diff. Repeated similar actions reinforce a
  source-typed belief about Lincoln's predictive accuracy on each tool, so
  the substrate's general belief loop will revise calibration over time.
  """

  import Ecto.Query

  alias Lincoln.Actions.Action
  alias Lincoln.Agents.Agent
  alias Lincoln.{Cognition, MCP, Memory, PubSubBroadcaster, Repo}

  require Logger

  @autonomous_tiers [0, 1]

  # ---------------------------------------------------------------------------
  # Lifecycle
  # ---------------------------------------------------------------------------

  @doc """
  Propose an action. Risk tier ≥ 2 is parked at `pending_approval` until a
  human approves it; tier 3 stays `proposed` and is treated as a dry-run.
  """
  def propose(%Agent{id: agent_id} = _agent, attrs) when is_map(attrs) do
    initial_status = initial_status_for(Map.get(attrs, :risk_tier) || Map.get(attrs, "risk_tier"))

    %Action{}
    |> Action.create_changeset(Map.put(attrs, :status, initial_status), agent_id)
    |> Repo.insert()
    |> tap_ok(&PubSubBroadcaster.broadcast_action_logged(agent_id, &1))
  end

  defp initial_status_for(tier) when tier in [2, "2"], do: "pending_approval"
  defp initial_status_for(_), do: "proposed"

  @doc """
  Returns whether this action is in a status that allows autonomous
  execution by an `ActionThought`.
  """
  def executable?(%Action{status: "proposed", risk_tier: tier}) when tier in @autonomous_tiers,
    do: true

  def executable?(_), do: false

  @doc "Counts actions ready for autonomous execution. Drives the impulse score."
  def count_executable(%Agent{id: agent_id}) do
    Repo.one(
      from(a in Action,
        where: a.agent_id == ^agent_id,
        where: a.status == "proposed",
        where: a.risk_tier in ^@autonomous_tiers,
        select: count(a.id)
      )
    ) || 0
  end

  @doc """
  Returns the next action to execute — highest prediction_confidence first
  (most likely to succeed → fastest calibration signal), then oldest.
  """
  def next_executable(%Agent{id: agent_id}) do
    Action
    |> where([a], a.agent_id == ^agent_id and a.status == "proposed")
    |> where([a], a.risk_tier in ^@autonomous_tiers)
    |> order_by([a], desc: a.prediction_confidence, asc: a.inserted_at)
    |> limit(1)
    |> Repo.one()
  end

  @doc """
  Approve a `pending_approval` action so it becomes executable. Phase 5
  does not yet expose this in the UI; Phase 7 wires it.
  """
  def approve(%Action{status: "pending_approval"} = action) do
    transition(action, %{status: "proposed"})
  end

  def approve(_), do: {:error, :not_pending_approval}

  @doc """
  Execute an action: call the configured MCP tool, persist outcome, write an
  observation memory, and feed calibration into the belief system.

  Options:
    * `:mcp_client` — module override for tests (must define `call_tool/4`)
  """
  def execute(%Action{} = action, opts \\ []) do
    if executable?(action) do
      do_execute(action, opts)
    else
      {:error, {:not_executable, action.status, action.risk_tier}}
    end
  end

  defp do_execute(action, opts) do
    mcp = Keyword.get(opts, :mcp_client, MCP.Client)

    {:ok, action} = transition(action, %{status: "executing"})

    started_at = DateTime.utc_now() |> DateTime.truncate(:second)

    case mcp.call_tool(server_atom(action.tool_server), action.tool_name, action.arguments) do
      {:ok, result} ->
        finalize_success(action, result, started_at)

      {:error, reason} ->
        finalize_failure(action, reason, started_at)
    end
  end

  defp finalize_success(action, result, started_at) do
    {:ok, memory} = record_outcome_memory(action, :success, result)
    {:ok, _} = calibrate_beliefs(action, :success)

    {:ok, updated} =
      transition(action, %{
        status: "executed",
        result: ensure_map(result),
        executed_at: started_at,
        observation_memory_id: memory.id
      })

    PubSubBroadcaster.broadcast_action_completed(action.agent_id, updated)
    {:ok, updated}
  end

  defp finalize_failure(action, reason, started_at) do
    {:ok, memory} = record_outcome_memory(action, :failure, reason)
    {:ok, _} = calibrate_beliefs(action, :failure)

    {:ok, updated} =
      transition(action, %{
        status: "failed",
        error: error_text(reason),
        executed_at: started_at,
        observation_memory_id: memory.id
      })

    PubSubBroadcaster.broadcast_action_completed(action.agent_id, updated)
    {:ok, updated}
  end

  defp transition(%Action{} = action, attrs) do
    action
    |> Action.transition_changeset(attrs)
    |> Repo.update()
  end

  # ---------------------------------------------------------------------------
  # Observation + calibration
  # ---------------------------------------------------------------------------

  defp record_outcome_memory(action, outcome, payload) do
    pred_conf_pct = round((action.prediction_confidence || 0.5) * 100)

    content =
      "Executed #{action.tool_name} (server #{action.tool_server}). " <>
        "Predicted '#{action.predicted_outcome || "—"}' " <>
        "with #{pred_conf_pct}% confidence. " <>
        outcome_phrase(outcome, payload)

    Repo.get(Lincoln.Agents.Agent, action.agent_id)
    |> Memory.create_memory(%{
      content: content,
      memory_type: "observation",
      importance: outcome_importance(outcome, action.prediction_confidence),
      source_context: %{
        "source" => "action_outcome",
        "action_id" => action.id,
        "tool_name" => action.tool_name,
        "tool_server" => action.tool_server,
        "outcome" => Atom.to_string(outcome),
        "prediction_confidence" => action.prediction_confidence,
        "goal_id" => action.goal_id,
        "processed_at" => DateTime.utc_now() |> DateTime.to_iso8601()
      }
    })
  end

  defp calibrate_beliefs(action, outcome) do
    agent = Repo.get(Lincoln.Agents.Agent, action.agent_id)
    statement = calibration_statement(action, outcome)

    {confidence, evidence} =
      case outcome do
        :success ->
          {0.6 + (action.prediction_confidence || 0.0) * 0.3,
           "Predicted #{action.tool_name} success (#{action.prediction_confidence}); succeeded."}

        :failure ->
          {0.3 + (1.0 - (action.prediction_confidence || 0.0)) * 0.3,
           "Predicted #{action.tool_name} success (#{action.prediction_confidence}); failed."}
      end

    Cognition.form_belief(agent, statement, "observation",
      confidence: clamp(confidence, 0.0, 1.0),
      evidence: evidence
    )
  rescue
    e ->
      Logger.warning("[Actions] Calibration belief failed: #{Exception.message(e)}")
      {:ok, :belief_skipped}
  end

  defp calibration_statement(action, :success),
    do:
      "Calling #{action.tool_name} via #{action.tool_server} reliably produces the predicted outcome"

  defp calibration_statement(action, :failure),
    do:
      "Calling #{action.tool_name} via #{action.tool_server} sometimes fails despite confident predictions"

  defp outcome_phrase(:success, %{} = payload),
    do: "Outcome: success — #{inspect_short(payload)}"

  defp outcome_phrase(:success, payload),
    do: "Outcome: success — #{inspect_short(payload)}"

  defp outcome_phrase(:failure, reason),
    do: "Outcome: failure — #{error_text(reason)}"

  defp outcome_importance(:success, conf) when is_number(conf) and conf < 0.4, do: 8
  defp outcome_importance(:failure, conf) when is_number(conf) and conf > 0.7, do: 9
  defp outcome_importance(:success, _conf), do: 6
  defp outcome_importance(:failure, _conf), do: 7

  defp inspect_short(value) do
    value
    |> inspect(limit: 5, printable_limit: 200)
    |> String.slice(0, 240)
  end

  defp error_text(reason) when is_binary(reason), do: reason
  defp error_text(reason), do: inspect(reason)

  defp ensure_map(value) when is_map(value), do: value
  defp ensure_map(value), do: %{"value" => inspect(value)}

  defp server_atom(value) when is_atom(value), do: value
  defp server_atom(value) when is_binary(value), do: String.to_atom(value)

  defp clamp(n, lo, hi), do: n |> max(lo) |> min(hi)

  defp tap_ok({:ok, value} = result, fun) do
    fun.(value)
    result
  end

  defp tap_ok(other, _fun), do: other

  # ---------------------------------------------------------------------------
  # Listing
  # ---------------------------------------------------------------------------

  @doc "Lists actions for an agent. Filters: :status, :risk_tier, :limit."
  def list_actions(%Agent{id: agent_id}, opts \\ []) do
    Action
    |> where([a], a.agent_id == ^agent_id)
    |> apply_filter(:status, Keyword.get(opts, :status))
    |> apply_filter(:risk_tier, Keyword.get(opts, :risk_tier))
    |> order_by([a], desc: a.inserted_at)
    |> limit(^Keyword.get(opts, :limit, 100))
    |> Repo.all()
  end

  defp apply_filter(query, _key, nil), do: query

  defp apply_filter(query, :status, statuses) when is_list(statuses),
    do: where(query, [a], a.status in ^statuses)

  defp apply_filter(query, :status, status), do: where(query, [a], a.status == ^status)
  defp apply_filter(query, :risk_tier, tier), do: where(query, [a], a.risk_tier == ^tier)

  def get_action!(id), do: Repo.get!(Action, id)
end
