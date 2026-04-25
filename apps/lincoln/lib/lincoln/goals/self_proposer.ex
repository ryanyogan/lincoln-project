defmodule Lincoln.Goals.SelfProposer do
  @moduledoc """
  Lets Lincoln propose its own goals — but never adopt them silently.

  Self-proposed goals enter the system with origin `"self"` and status
  `"pending_user_approval"`. They show up in the Goals UI with an approve /
  reject affordance; only when a human approves does a self-proposed goal
  become active and join the attention competition.

  This is the safety gate for the most autonomy-extending capability in
  the substrate. It is intentionally minimal in Phase 7 — the *trigger*
  logic for when Lincoln should propose a goal (e.g. recurring questions,
  noticed patterns) is left for future work; this module just provides
  the approval-gated insertion path.
  """

  alias Lincoln.{Agents, Goals}

  require Logger

  @doc """
  Propose a self-goal for the agent. The goal is created in
  `pending_user_approval` status with origin `"self"` and is NOT yet
  active.

  Returns `{:ok, goal}` on success.
  """
  def propose_self_goal(%Agents.Agent{} = agent, statement, opts \\ [])
      when is_binary(statement) do
    attrs = %{
      statement: statement,
      origin: "self",
      status: "pending_user_approval",
      priority: Keyword.get(opts, :priority, 5),
      success_criteria: Keyword.get(opts, :success_criteria, %{})
    }

    Logger.info("[SelfProposer] Proposing self-goal: #{String.slice(statement, 0, 80)}")
    Goals.create_goal(agent, attrs)
  end

  @doc """
  Approve a pending self-goal — moves it to active status so it joins the
  attention competition.
  """
  def approve(%Goals.Goal{status: "pending_user_approval"} = goal) do
    Goals.update_status(goal, "active")
  end

  def approve(_other), do: {:error, :not_pending_approval}

  @doc """
  Reject a pending self-goal — it is marked abandoned but kept on record so
  Lincoln learns that this kind of goal does not get human approval.
  """
  def reject(%Goals.Goal{status: "pending_user_approval"} = goal) do
    Goals.update_status(goal, "abandoned")
  end

  def reject(_other), do: {:error, :not_pending_approval}
end
