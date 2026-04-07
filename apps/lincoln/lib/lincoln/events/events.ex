defmodule Lincoln.Events do
  @moduledoc """
  Context for Lincoln's event system.
  Events are emitted when Lincoln experiences something notable:
  - Struggles (gave up, slow, low confidence)
  - Learning (beliefs formed, revised)
  - Improvements (opportunities, changes applied)
  """

  import Ecto.Query
  alias Lincoln.Events.{Event, ImprovementOpportunity}
  alias Lincoln.Repo

  # =============================================================================
  # Events CRUD
  # =============================================================================

  def list_events(agent, opts \\ []) do
    limit = Keyword.get(opts, :limit, 50)
    type = Keyword.get(opts, :type)
    since = Keyword.get(opts, :since)

    query =
      from(e in Event,
        where: e.agent_id == ^agent.id,
        order_by: [desc: e.inserted_at],
        limit: ^limit
      )

    query = if type, do: where(query, [e], e.type == ^type), else: query
    query = if since, do: where(query, [e], e.inserted_at >= ^since), else: query

    Repo.all(query)
  end

  def get_event!(id), do: Repo.get!(Event, id)

  def create_event(attrs) do
    %Event{}
    |> Event.changeset(attrs)
    |> Repo.insert()
  end

  def count_events(agent, type, since) do
    from(e in Event,
      where: e.agent_id == ^agent.id and e.type == ^type and e.inserted_at >= ^since,
      select: count(e.id)
    )
    |> Repo.one()
  end

  def recent_event_types(agent, limit \\ 10) do
    from(e in Event,
      where: e.agent_id == ^agent.id,
      group_by: e.type,
      order_by: [desc: count(e.id)],
      limit: ^limit,
      select: {e.type, count(e.id)}
    )
    |> Repo.all()
  end

  # =============================================================================
  # Improvement Opportunities CRUD
  # =============================================================================

  def list_improvement_opportunities(agent, opts \\ []) do
    status = Keyword.get(opts, :status, "pending")
    limit = Keyword.get(opts, :limit, 20)

    from(io in ImprovementOpportunity,
      where: io.agent_id == ^agent.id,
      where: io.status == ^status,
      order_by: [desc: io.priority, asc: io.inserted_at],
      limit: ^limit
    )
    |> Repo.all()
  end

  def get_improvement_opportunity!(id), do: Repo.get!(ImprovementOpportunity, id)

  def create_improvement_opportunity(attrs) do
    %ImprovementOpportunity{}
    |> ImprovementOpportunity.changeset(attrs)
    |> Repo.insert()
  end

  def update_improvement_opportunity(opportunity, attrs) do
    opportunity
    |> ImprovementOpportunity.changeset(attrs)
    |> Repo.update()
  end

  def next_pending_opportunity(agent) do
    from(io in ImprovementOpportunity,
      where: io.agent_id == ^agent.id and io.status == "pending",
      order_by: [desc: io.priority, asc: io.inserted_at],
      limit: 1
    )
    |> Repo.one()
  end

  def current_in_progress(agent) do
    from(io in ImprovementOpportunity,
      where: io.agent_id == ^agent.id and io.status == "in_progress",
      limit: 1
    )
    |> Repo.one()
  end

  def mark_opportunity_in_progress(opportunity) do
    opportunity
    |> ImprovementOpportunity.mark_in_progress()
    |> Repo.update()
  end

  def mark_opportunity_completed(opportunity, outcome) do
    opportunity
    |> ImprovementOpportunity.mark_completed(outcome)
    |> Repo.update()
  end

  def mark_opportunity_failed(opportunity, reason) do
    opportunity
    |> ImprovementOpportunity.mark_failed(reason)
    |> Repo.update()
  end
end
