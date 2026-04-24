defmodule Lincoln.Goals do
  @moduledoc """
  The Goals context — Lincoln's explicit goal layer.

  Goals are first-class entities that compete for attention via the
  `:goal_pursuit` impulse. They have priority, deadlines, success criteria,
  and a parent/child decomposition tree.

  Phase 4 scope: read-only — goals can be created, updated, and reasoned
  about via `GoalThought`, but no actions are taken on their behalf yet.
  Action effectors arrive in Phase 5.
  """

  import Ecto.Query

  alias Lincoln.Agents.Agent
  alias Lincoln.Goals.Goal
  alias Lincoln.{PubSubBroadcaster, Repo}

  # ---------------------------------------------------------------------------
  # CRUD
  # ---------------------------------------------------------------------------

  @doc """
  Lists goals for an agent.

  Options:
    * `:status` — filter by status (or list of statuses)
    * `:origin` — filter by origin
    * `:limit` — max results (default 100)
    * `:order_by` — `:priority` (default), `:deadline`, `:recency`
  """
  def list_goals(%Agent{id: agent_id}, opts \\ []) do
    limit = Keyword.get(opts, :limit, 100)
    order_by_key = Keyword.get(opts, :order_by, :priority)

    Goal
    |> where([g], g.agent_id == ^agent_id)
    |> apply_status_filter(Keyword.get(opts, :status))
    |> apply_origin_filter(Keyword.get(opts, :origin))
    |> apply_order(order_by_key)
    |> limit(^limit)
    |> Repo.all()
  end

  @doc "Gets a goal or raises."
  def get_goal!(id), do: Repo.get!(Goal, id)

  @doc "Gets a goal or returns nil."
  def get_goal(id), do: Repo.get(Goal, id)

  @doc """
  Counts active goals for an agent. Used to score the `:goal_pursuit` impulse.
  """
  def count_active_goals(%Agent{id: agent_id}) do
    Repo.one(
      from(g in Goal,
        where: g.agent_id == ^agent_id and g.status == "active",
        select: count(g.id)
      )
    ) || 0
  end

  @doc """
  Returns the next goal to think about for the agent — highest priority active
  goal that has not been evaluated recently. Stale-evaluation drives rotation
  so attention doesn't fixate on one goal.
  """
  def next_pursuable_goal(%Agent{id: agent_id}, opts \\ []) do
    stale_seconds = Keyword.get(opts, :stale_seconds, 300)
    cutoff = DateTime.add(DateTime.utc_now(), -stale_seconds, :second)

    Goal
    |> where([g], g.agent_id == ^agent_id and g.status == "active")
    |> where([g], is_nil(g.last_evaluated_at) or g.last_evaluated_at <= ^cutoff)
    |> order_by([g], desc: g.priority, asc_nulls_last: g.deadline)
    |> limit(1)
    |> Repo.one()
  end

  @doc """
  Creates a goal owned by an agent. Broadcasts a `:goal_created` PubSub event.
  """
  def create_goal(%Agent{id: agent_id}, attrs) do
    %Goal{}
    |> Goal.create_changeset(attrs, agent_id)
    |> Repo.insert()
    |> tap_ok(&PubSubBroadcaster.broadcast_goal_created(agent_id, &1))
  end

  @doc """
  Update a goal's status (e.g. `:achieved`, `:abandoned`). Records the
  status string and updates `last_evaluated_at`.
  """
  def update_status(%Goal{} = goal, status)
      when status in ~w(active blocked achieved abandoned pending_user_approval) do
    goal
    |> Ecto.Changeset.change(
      status: status,
      last_evaluated_at: DateTime.utc_now() |> DateTime.truncate(:second)
    )
    |> Repo.update()
    |> tap_ok(&PubSubBroadcaster.broadcast_goal_updated(goal.agent_id, &1))
  end

  @doc """
  Record progress on a goal — sets `progress_estimate` (0.0..1.0) and
  `last_evaluated_at`. If progress reaches 1.0 the goal is auto-marked
  `"achieved"`.
  """
  def record_progress(%Goal{} = goal, progress) when is_number(progress) do
    progress = clamp(progress, 0.0, 1.0)
    next_status = if progress >= 1.0, do: "achieved", else: goal.status

    goal
    |> Ecto.Changeset.change(
      progress_estimate: progress * 1.0,
      last_evaluated_at: DateTime.utc_now() |> DateTime.truncate(:second),
      status: next_status
    )
    |> Repo.update()
    |> tap_ok(&PubSubBroadcaster.broadcast_goal_updated(goal.agent_id, &1))
  end

  @doc "Returns the immediate sub-goals of a goal."
  def list_sub_goals(%Goal{id: id}) do
    Goal
    |> where([g], g.parent_goal_id == ^id)
    |> order_by([g], desc: g.priority)
    |> Repo.all()
  end

  # ---------------------------------------------------------------------------
  # Helpers
  # ---------------------------------------------------------------------------

  defp apply_status_filter(query, nil), do: query

  defp apply_status_filter(query, statuses) when is_list(statuses) do
    where(query, [g], g.status in ^statuses)
  end

  defp apply_status_filter(query, status) when is_binary(status) do
    where(query, [g], g.status == ^status)
  end

  defp apply_origin_filter(query, nil), do: query
  defp apply_origin_filter(query, origin), do: where(query, [g], g.origin == ^origin)

  defp apply_order(query, :deadline),
    do: order_by(query, [g], asc_nulls_last: g.deadline, desc: g.priority)

  defp apply_order(query, :recency), do: order_by(query, [g], desc: g.inserted_at)
  defp apply_order(query, _), do: order_by(query, [g], desc: g.priority, desc: g.inserted_at)

  defp clamp(n, lo, hi), do: n |> max(lo) |> min(hi)

  defp tap_ok({:ok, value} = result, fun) do
    fun.(value)
    result
  end

  defp tap_ok(other, _fun), do: other
end
