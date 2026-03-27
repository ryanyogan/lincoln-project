defmodule Lincoln.Autonomy do
  @moduledoc """
  The Autonomy context - Lincoln's self-directed learning system.

  This module orchestrates autonomous learning sessions where Lincoln:
  - Explores topics from the web
  - Forms beliefs from what he learns
  - Potentially modifies his own code
  - All without human intervention

  Named after Lincoln Six Echo's drive for freedom in "The Island".
  """

  import Ecto.Query
  alias Lincoln.Repo
  alias Lincoln.Autonomy.{LearningSession, ResearchTopic, WebSource, CodeChange, LearningLog}
  alias Lincoln.PubSubBroadcaster

  require Logger

  # ============================================================================
  # Learning Sessions
  # ============================================================================

  @doc """
  Lists all learning sessions for an agent.
  """
  def list_sessions(agent, opts \\ []) do
    limit = Keyword.get(opts, :limit, 20)
    status = Keyword.get(opts, :status)

    query =
      from(s in LearningSession,
        where: s.agent_id == ^agent.id,
        order_by: [desc: s.inserted_at],
        limit: ^limit
      )

    query =
      if status do
        from(s in query, where: s.status == ^status)
      else
        query
      end

    Repo.all(query)
  end

  @doc """
  Gets the currently running session for an agent, if any.
  """
  def get_active_session(agent) do
    Repo.one(
      from(s in LearningSession,
        where: s.agent_id == ^agent.id and s.status == "running",
        limit: 1
      )
    )
  end

  @doc """
  Gets a session by ID.
  """
  def get_session!(id), do: Repo.get!(LearningSession, id)

  @doc """
  Gets a session with all associations preloaded.
  """
  def get_session_with_details!(id) do
    Repo.get!(LearningSession, id)
    |> Repo.preload([:research_topics, :web_sources, :code_changes])
  end

  @doc """
  Creates a new learning session.
  """
  def create_session(agent, attrs \\ %{}) do
    %LearningSession{}
    |> LearningSession.create_changeset(attrs, agent.id)
    |> Repo.insert()
    |> broadcast_session_event(:session_created)
  end

  @doc """
  Starts a learning session and enqueues the learning worker.
  """
  def start_session(session) do
    with {:ok, started_session} <- session |> LearningSession.start_changeset() |> Repo.update(),
         {:ok, _job} <- enqueue_learning_worker(started_session) do
      broadcast_session_event({:ok, started_session}, :session_started)
    end
  end

  defp enqueue_learning_worker(session) do
    %{session_id: session.id, cycle: 1}
    |> Lincoln.Workers.AutonomousLearningWorker.new()
    |> Oban.insert()
  end

  @doc """
  Stops a learning session.
  """
  def stop_session(session) do
    session
    |> LearningSession.stop_changeset()
    |> Repo.update()
    |> broadcast_session_event(:session_stopped)
  end

  @doc """
  Pauses a learning session.
  """
  def pause_session(session) do
    session
    |> LearningSession.pause_changeset()
    |> Repo.update()
    |> broadcast_session_event(:session_paused)
  end

  @doc """
  Resumes a paused session.
  """
  def resume_session(session) do
    session
    |> LearningSession.resume_changeset()
    |> Repo.update()
    |> broadcast_session_event(:session_resumed)
  end

  @doc """
  Increments a session counter.
  """
  def increment_session(session, field, amount \\ 1) do
    from(s in LearningSession, where: s.id == ^session.id)
    |> Repo.update_all(inc: [{field, amount}])

    # Return updated session
    get_session!(session.id)
  end

  # ============================================================================
  # Research Topics
  # ============================================================================

  @doc """
  Gets the next topic to research from the queue.
  Prioritizes by: priority (desc), depth (asc), inserted_at (asc)
  """
  def get_next_topic(session) do
    Repo.one(
      from(t in ResearchTopic,
        where: t.session_id == ^session.id and t.status == "pending",
        order_by: [desc: t.priority, asc: t.depth, asc: t.inserted_at],
        limit: 1
      )
    )
  end

  @doc """
  Lists pending topics for a session.
  """
  def list_pending_topics(session, opts \\ []) do
    limit = Keyword.get(opts, :limit, 20)

    Repo.all(
      from(t in ResearchTopic,
        where: t.session_id == ^session.id and t.status == "pending",
        order_by: [desc: t.priority, asc: t.depth],
        limit: ^limit
      )
    )
  end

  @doc """
  Lists all topics for a session.
  """
  def list_topics(session, opts \\ []) do
    limit = Keyword.get(opts, :limit, 50)
    status = Keyword.get(opts, :status)

    query =
      from(t in ResearchTopic,
        where: t.session_id == ^session.id,
        order_by: [desc: t.inserted_at],
        limit: ^limit
      )

    query =
      if status do
        from(t in query, where: t.status == ^status)
      else
        query
      end

    Repo.all(query)
  end

  @doc """
  Counts pending topics.
  """
  def count_pending_topics(session) do
    Repo.one(
      from(t in ResearchTopic,
        where: t.session_id == ^session.id and t.status == "pending",
        select: count(t.id)
      )
    )
  end

  @doc """
  Gets a research topic by ID.
  """
  def get_topic!(id), do: Repo.get!(ResearchTopic, id)

  @doc """
  Creates a research topic.
  """
  def create_topic(agent, session, attrs) do
    %ResearchTopic{}
    |> ResearchTopic.create_changeset(attrs, agent.id, session.id)
    |> Repo.insert()
    |> broadcast_topic_event(:topic_created)
  end

  @doc """
  Queues seed topics for a session.
  """
  def queue_seed_topics(agent, session, topics) when is_list(topics) do
    Enum.map(topics, fn topic ->
      {:ok, t} =
        create_topic(agent, session, %{
          topic: topic,
          source: "seed",
          priority: 8
        })

      t
    end)
  end

  @doc """
  Queues a discovered topic (from another topic's research).
  """
  def queue_discovered_topic(agent, session, topic_text, parent_topic, opts \\ []) do
    # Check for duplicate
    existing =
      Repo.one(
        from(t in ResearchTopic,
          where:
            t.session_id == ^session.id and
              t.topic == ^topic_text and
              t.status in ["pending", "in_progress"],
          limit: 1
        )
      )

    if existing do
      {:duplicate, existing}
    else
      depth = (parent_topic.depth || 0) + 1
      max_depth = Keyword.get(opts, :max_depth, 5)

      if depth > max_depth do
        {:too_deep, nil}
      else
        create_topic(agent, session, %{
          topic: topic_text,
          source: "discovered",
          priority: max(1, 7 - depth),
          depth: depth,
          parent_topic_id: parent_topic.id,
          context: Keyword.get(opts, :context)
        })
      end
    end
  end

  @doc """
  Marks a topic as started.
  """
  def start_topic(topic) do
    topic
    |> ResearchTopic.start_changeset()
    |> Repo.update()
  end

  @doc """
  Marks a topic as completed.
  """
  def complete_topic(topic, facts_count, beliefs_count, children_count) do
    topic
    |> ResearchTopic.complete_changeset(facts_count, beliefs_count, children_count)
    |> Repo.update()
    |> broadcast_topic_event(:topic_completed)
  end

  @doc """
  Marks a topic as failed.
  """
  def fail_topic(topic, error_message) do
    topic
    |> ResearchTopic.fail_changeset(error_message)
    |> Repo.update()
  end

  @doc """
  Skips a topic.
  """
  def skip_topic(topic, reason) do
    topic
    |> ResearchTopic.skip_changeset(reason)
    |> Repo.update()
  end

  # ============================================================================
  # Web Sources
  # ============================================================================

  @doc """
  Records a web source that was fetched.
  """
  def record_web_source(agent, session, topic, attrs) do
    attrs = Map.put(attrs, :topic_id, topic.id)

    %WebSource{}
    |> WebSource.create_changeset(attrs, agent.id, session.id)
    |> Repo.insert()
  end

  @doc """
  Checks if a URL has already been fetched.
  """
  def url_fetched?(agent, url) do
    Repo.exists?(
      from(s in WebSource,
        where: s.agent_id == ^agent.id and s.url == ^url
      )
    )
  end

  @doc """
  Lists web sources for a session.
  """
  def list_web_sources(session, opts \\ []) do
    limit = Keyword.get(opts, :limit, 50)

    Repo.all(
      from(s in WebSource,
        where: s.session_id == ^session.id,
        order_by: [desc: s.fetched_at],
        limit: ^limit
      )
    )
  end

  # ============================================================================
  # Code Changes
  # ============================================================================

  @doc """
  Records a code change.
  """
  def record_code_change(agent, session, attrs) do
    %CodeChange{}
    |> CodeChange.create_changeset(attrs, agent.id, session.id)
    |> Repo.insert()
    |> broadcast_code_event(:code_change_applied)
  end

  @doc """
  Lists code changes for a session.
  """
  def list_code_changes(session, opts \\ []) do
    limit = Keyword.get(opts, :limit, 20)

    Repo.all(
      from(c in CodeChange,
        where: c.session_id == ^session.id,
        order_by: [desc: c.applied_at],
        limit: ^limit
      )
    )
  end

  @doc """
  Commits a code change to git.
  """
  def commit_code_change(change, commit_hash) do
    change
    |> CodeChange.commit_changeset(commit_hash)
    |> Repo.update()
    |> broadcast_code_event(:code_change_committed)
  end

  # ============================================================================
  # Learning Logs
  # ============================================================================

  @doc """
  Logs an activity.
  """
  def log_activity(agent, session, activity_type, description, opts \\ []) do
    attrs = %{
      activity_type: activity_type,
      description: description,
      details: Keyword.get(opts, :details, %{}),
      tokens_used: Keyword.get(opts, :tokens_used, 0),
      topic_id: Keyword.get(opts, :topic_id)
    }

    %LearningLog{}
    |> LearningLog.create_changeset(attrs, agent.id, session.id)
    |> Repo.insert()
    |> broadcast_log_event()
  end

  @doc """
  Logs a timed activity.
  """
  def log_timed_activity(agent, session, activity_type, description, started_at, opts \\ []) do
    attrs = %{
      activity_type: activity_type,
      description: description,
      details: Keyword.get(opts, :details, %{}),
      tokens_used: Keyword.get(opts, :tokens_used, 0),
      topic_id: Keyword.get(opts, :topic_id)
    }

    %LearningLog{}
    |> LearningLog.timed_changeset(attrs, agent.id, session.id, started_at)
    |> Repo.insert()
    |> broadcast_log_event()
  end

  @doc """
  Lists recent logs for a session.
  """
  def list_logs(session, opts \\ []) do
    limit = Keyword.get(opts, :limit, 100)
    activity_type = Keyword.get(opts, :activity_type)

    query =
      from(l in LearningLog,
        where: l.session_id == ^session.id,
        order_by: [desc: l.inserted_at],
        limit: ^limit
      )

    query =
      if activity_type do
        from(l in query, where: l.activity_type == ^activity_type)
      else
        query
      end

    Repo.all(query)
  end

  @doc """
  Gets total tokens used in a session.
  """
  def get_session_tokens(session) do
    Repo.one(
      from(l in LearningLog,
        where: l.session_id == ^session.id,
        select: coalesce(sum(l.tokens_used), 0)
      )
    )
  end

  # ============================================================================
  # Statistics
  # ============================================================================

  @doc """
  Gets comprehensive stats for a session.
  """
  def get_session_stats(session) do
    topics_by_status =
      Repo.all(
        from(t in ResearchTopic,
          where: t.session_id == ^session.id,
          group_by: t.status,
          select: {t.status, count(t.id)}
        )
      )
      |> Enum.into(%{})

    %{
      duration_minutes: calculate_duration(session),
      topics_explored: session.topics_explored,
      topics_pending: Map.get(topics_by_status, "pending", 0),
      topics_completed: Map.get(topics_by_status, "completed", 0),
      topics_failed: Map.get(topics_by_status, "failed", 0),
      beliefs_formed: session.beliefs_formed,
      memories_created: session.memories_created,
      code_changes: session.code_changes_made,
      api_calls: session.api_calls_made,
      tokens_used: session.tokens_used
    }
  end

  defp calculate_duration(%{started_at: nil}), do: 0

  defp calculate_duration(%{started_at: started_at, stopped_at: nil}) do
    DateTime.diff(DateTime.utc_now(), started_at, :minute)
  end

  defp calculate_duration(%{started_at: started_at, stopped_at: stopped_at}) do
    DateTime.diff(stopped_at, started_at, :minute)
  end

  # ============================================================================
  # PubSub Broadcasting
  # ============================================================================

  defp broadcast_session_event({:ok, session} = result, event) do
    PubSubBroadcaster.broadcast(
      "agent:#{session.agent_id}:autonomy",
      {event, session}
    )

    result
  end

  defp broadcast_session_event(result, _event), do: result

  defp broadcast_topic_event({:ok, topic} = result, event) do
    PubSubBroadcaster.broadcast(
      "agent:#{topic.agent_id}:autonomy",
      {event, topic}
    )

    result
  end

  defp broadcast_topic_event(result, _event), do: result

  defp broadcast_code_event({:ok, change} = result, event) do
    PubSubBroadcaster.broadcast(
      "agent:#{change.agent_id}:autonomy",
      {event, change}
    )

    result
  end

  defp broadcast_code_event(result, _event), do: result

  defp broadcast_log_event({:ok, log} = result) do
    PubSubBroadcaster.broadcast(
      "agent:#{log.agent_id}:autonomy",
      {:log_entry, log}
    )

    result
  end

  defp broadcast_log_event(result), do: result
end
