defmodule Lincoln.Events.ImprovementQueue do
  @moduledoc """
  Manages the queue of improvement opportunities.
  Works through them one at a time.
  """

  alias Lincoln.Events

  @doc "Enqueue a new improvement opportunity"
  def enqueue(agent, attrs) do
    Events.create_improvement_opportunity(Map.put(attrs, :agent_id, agent.id))
  end

  @doc "Get the next pending opportunity (highest priority, oldest first)"
  def next(agent) do
    Events.next_pending_opportunity(agent)
  end

  @doc "Check if there's currently an improvement in progress"
  def currently_working?(agent) do
    Events.current_in_progress(agent) != nil
  end

  @doc "Mark an opportunity as in progress"
  def mark_in_progress(opportunity) do
    Events.mark_opportunity_in_progress(opportunity)
  end

  @doc "Mark an opportunity as completed with outcome"
  def mark_completed(opportunity, outcome)
      when outcome in ["improved", "no_change", "degraded"] do
    Events.mark_opportunity_completed(opportunity, outcome)
  end

  @doc "Mark an opportunity as failed"
  def mark_failed(opportunity, reason) do
    Events.mark_opportunity_failed(opportunity, reason)
  end

  @doc "Link a code change to an opportunity"
  def link_change(opportunity, code_change) do
    Events.update_improvement_opportunity(opportunity, %{code_change_id: code_change.id})
  end

  @doc "Get queue status for an agent"
  def status(agent) do
    pending = Events.list_improvement_opportunities(agent, status: "pending") |> length()
    in_progress = if currently_working?(agent), do: 1, else: 0
    completed = Events.list_improvement_opportunities(agent, status: "completed") |> length()
    failed = Events.list_improvement_opportunities(agent, status: "failed") |> length()

    %{
      pending: pending,
      in_progress: in_progress,
      completed: completed,
      failed: failed,
      total: pending + in_progress + completed + failed
    }
  end
end
