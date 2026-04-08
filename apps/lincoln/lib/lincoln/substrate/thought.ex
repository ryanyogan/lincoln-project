defmodule Lincoln.Substrate.Thought do
  @moduledoc """
  A single cognitive act — a supervised OTP process with its own lifecycle.

  Each Thought is spawned by ThoughtSupervisor when the Substrate decides
  something is worth thinking about. The Thought owns its execution, records
  its results, broadcasts lifecycle events, and terminates when done.

  This is the architectural claim: thoughts in Lincoln are processes,
  not function calls. They are observable, interruptible, and supervised.
  Python cannot do this.
  """

  use GenServer
  require Logger

  alias Lincoln.{Agents, Narratives, PubSubBroadcaster}
  alias Lincoln.Substrate.{InferenceTier, ThoughtSupervisor, Trajectory}

  defstruct [
    :id,
    :agent_id,
    :belief,
    :attention_score,
    :tier,
    :status,
    :result,
    :started_at,
    :completed_at,
    :parent_id,
    :is_narrative,
    :narrative_tick,
    pending_children: %{},
    child_results: []
  ]

  # ============================================================================
  # Public API
  # ============================================================================

  def start_link(opts) when is_map(opts) do
    GenServer.start_link(__MODULE__, opts)
  end

  def child_spec(opts) when is_map(opts) do
    %{
      id: {__MODULE__, Map.get(opts, :id, make_ref())},
      start: {__MODULE__, :start_link, [opts]},
      type: :worker,
      restart: :temporary
    }
  end

  @doc "Returns the current state of this Thought process."
  def get_state(pid), do: GenServer.call(pid, :get_state)

  @doc "Interrupt this thought — it will terminate gracefully after broadcasting the event."
  def interrupt(pid), do: GenServer.cast(pid, :interrupt)

  @doc """
  Spawn a child thought that explores a related belief.
  The child runs under the same ThoughtSupervisor with parent_id set.
  Returns {:ok, child_id} or {:error, reason}.
  """
  def spawn_child(parent_pid, belief, score) do
    GenServer.call(parent_pid, {:spawn_child, belief, score})
  end

  # ============================================================================
  # GenServer callbacks
  # ============================================================================

  @impl true
  def init(%{agent_id: agent_id, belief: belief, attention_score: score} = opts) do
    id = Map.get(opts, :id) || Ecto.UUID.generate()
    tier = InferenceTier.select_tier(score)

    state = %__MODULE__{
      id: id,
      agent_id: agent_id,
      belief: belief,
      attention_score: score,
      tier: tier,
      status: :initializing,
      result: nil,
      started_at: DateTime.utc_now(),
      completed_at: nil,
      parent_id: Map.get(opts, :parent_id),
      pending_children: %{},
      child_results: [],
      is_narrative: Map.get(opts, :is_narrative, false),
      narrative_tick: Map.get(opts, :narrative_tick, 0)
    }

    belief_statement = get_statement(belief)

    PubSubBroadcaster.broadcast_thought_event(
      agent_id,
      {:thought_spawned, id, belief_statement, tier, Map.get(opts, :parent_id)}
    )

    Logger.debug("[Thought #{id}] Spawned: #{tier} — #{belief_statement}")

    {:ok, state, {:continue, :execute}}
  end

  @impl true
  def handle_continue(:execute, %{tier: :local} = state) do
    new_state = execute_local(state)
    finalize(new_state)
    {:stop, :normal, new_state}
  end

  @impl true
  def handle_continue(:execute, %{is_narrative: true} = state) do
    Logger.info("[Thought #{state.id}] Narrative reflection at tick #{state.narrative_tick}")
    _task = Task.async(fn -> run_narrative_llm(state) end)
    {:noreply, %{state | status: :awaiting_llm}}
  end

  @impl true
  def handle_continue(:execute, state) do
    # Don't spawn grandchildren — only top-level thoughts explore
    if state.parent_id do
      _task = Task.async(fn -> run_llm(state.belief, state.tier) end)
      {:noreply, %{state | status: :awaiting_llm}}
    else
      case find_exploration_candidates(state) do
        [] ->
          _task = Task.async(fn -> run_llm(state.belief, state.tier) end)
          {:noreply, %{state | status: :awaiting_llm}}

        candidates ->
          Logger.debug(
            "[Thought #{state.id}] Spawning #{length(candidates)} children for exploration"
          )

          new_state = spawn_exploration_children(candidates, state)
          {:noreply, new_state}
      end
    end
  end

  # Child thought completed — track it, synthesize when all done
  @impl true
  def handle_info({:thought_completed, child_id, result}, state)
      when is_map_key(state.pending_children, child_id) do
    pending = Map.put(state.pending_children, child_id, result)
    child_results = [result | state.child_results]
    new_state = %{state | pending_children: pending, child_results: child_results}

    if Enum.all?(pending, fn {_id, r} -> r != nil end) do
      Logger.debug("[Thought #{state.id}] All #{map_size(pending)} children done, synthesizing")
      _task = Task.async(fn -> run_llm_with_children(state.belief, state.tier, child_results) end)
      {:noreply, %{new_state | status: :awaiting_llm}}
    else
      remaining = Enum.count(pending, fn {_id, r} -> r == nil end)
      Logger.debug("[Thought #{state.id}] Waiting for #{remaining} more children")
      {:noreply, new_state}
    end
  end

  # Non-child thought_completed events (from siblings) — ignore
  def handle_info({:thought_completed, _other_id, _result}, state), do: {:noreply, state}

  # Other thought events from the subscription — ignore
  def handle_info({:thought_spawned, _id, _statement, _tier, _parent_id}, state),
    do: {:noreply, state}

  def handle_info({:thought_interrupted, _id, _reason}, state), do: {:noreply, state}
  def handle_info({:thought_failed, _id, _reason}, state), do: {:noreply, state}

  @impl true
  def handle_info({ref, result}, state) when is_reference(ref) do
    Process.demonitor(ref, [:flush])

    case result do
      {:ok, :skipped} ->
        new_state = %{
          state
          | status: :completed,
            result: "Skipped (budget constraint)",
            completed_at: DateTime.utc_now()
        }

        finalize(new_state)
        {:stop, :normal, new_state}

      {:ok, text} ->
        new_state = %{state | status: :completed, result: text, completed_at: DateTime.utc_now()}

        finalize(new_state)
        {:stop, :normal, new_state}

      {:error, reason} ->
        Logger.warning("[Thought #{state.id}] LLM failed: #{inspect(reason)}")
        new_state = %{state | status: :failed, completed_at: DateTime.utc_now()}

        PubSubBroadcaster.broadcast_thought_event(
          state.agent_id,
          {:thought_failed, state.id, reason}
        )

        {:stop, {:error, reason}, new_state}
    end
  end

  def handle_info({:DOWN, _ref, :process, _pid, _reason}, state) do
    {:noreply, state}
  end

  @impl true
  def handle_info(_msg, state), do: {:noreply, state}

  @impl true
  def handle_cast(:interrupt, state) do
    Logger.debug("[Thought #{state.id}] Interrupted — preempted by higher-priority belief")

    PubSubBroadcaster.broadcast_thought_event(
      state.agent_id,
      {:thought_interrupted, state.id, :preempted}
    )

    {:stop, :interrupted, state}
  end

  @impl true
  def handle_call({:spawn_child, belief, score}, _from, state) do
    case do_spawn_child(belief, score, state) do
      {:ok, child_id, new_state} -> {:reply, {:ok, child_id}, new_state}
      {:error, reason} -> {:reply, {:error, reason}, state}
    end
  end

  @impl true
  def handle_call(:get_state, _from, state) do
    {:reply, state, state}
  end

  @impl true
  def terminate(:interrupted, state) do
    Logger.info("[Thought #{state.id}] Terminated: interrupted (preempted)")
    :ok
  end

  def terminate(reason, state) do
    Logger.debug("[Thought #{state.id}] Terminating: #{inspect(reason)}")
    :ok
  end

  # ============================================================================
  # Private
  # ============================================================================

  defp execute_local(state) do
    belief_statement = get_statement(state.belief)
    confidence = get_confidence(state.belief)
    summary = "Contemplating: #{belief_statement} (confidence: #{Float.round(confidence, 2)})"
    %{state | status: :completed, result: summary, completed_at: DateTime.utc_now()}
  end

  defp run_llm(belief, tier) do
    statement = get_statement(belief)

    messages = [
      %{role: "system", content: "You are reflecting on a belief. Be concise (2-3 sentences)."},
      %{role: "user", content: "Reflect on this belief: #{statement}"}
    ]

    InferenceTier.execute_at_tier(tier, messages, [])
  end

  defp run_llm_with_children(belief, tier, child_results) do
    statement = get_statement(belief)

    child_context =
      child_results
      |> Enum.reject(&is_nil/1)
      |> Enum.with_index(1)
      |> Enum.map_join("\n", fn {result, i} -> "#{i}. #{result}" end)

    messages = [
      %{
        role: "system",
        content:
          "You are synthesizing insights from parallel explorations. Be concise (3-4 sentences)."
      },
      %{
        role: "user",
        content: """
        Main belief: #{statement}

        Parallel explorations of related beliefs:
        #{child_context}

        Synthesize these into a coherent reflection on the main belief.
        """
      }
    ]

    InferenceTier.execute_at_tier(tier, messages, [])
  end

  defp run_narrative_llm(state) do
    trajectory_summary =
      try do
        Trajectory.summary(state.agent_id, hours: 1)
      rescue
        _ -> %{total_events: 0, thought_counts: %{completed: 0}}
      end

    completed_thoughts = get_in(trajectory_summary, [:thought_counts, :completed]) || 0

    messages = [
      %{
        role: "system",
        content: """
        You are Lincoln's introspective voice. Write a short autobiographical passage
        (3-5 sentences) in first person describing what you have been thinking about,
        what you have noticed, and how your understanding has shifted recently.
        Be specific about beliefs and topics you have encountered.
        Be honest about uncertainties. Write as a continuous cognitive entity.
        Begin with "I have been..." or "In the last stretch of ticks..."
        """
      },
      %{
        role: "user",
        content: """
        Recent activity (last hour):
        - Substrate events processed: #{trajectory_summary.total_events}
        - Thoughts completed: #{completed_thoughts}
        - Current tick: #{state.narrative_tick}

        Write your reflection now.
        """
      }
    ]

    case InferenceTier.execute_at_tier(:claude, messages, []) do
      {:ok, text} ->
        Task.start(fn ->
          try do
            Narratives.create_reflection(state.agent_id, %{
              content: text,
              tick_number: state.narrative_tick,
              period_start_tick: max(0, state.narrative_tick - 200),
              period_end_tick: state.narrative_tick,
              thought_count: completed_thoughts
            })
          rescue
            e ->
              Logger.warning("[Thought] Narrative persist failed: #{Exception.message(e)}")
          end
        end)

        {:ok, text}

      {:error, reason} ->
        Logger.warning("[Thought] Narrative LLM failed: #{inspect(reason)}")
        {:error, reason}
    end
  end

  defp find_exploration_candidates(state) do
    import Ecto.Query

    belief_id =
      Map.get(state.belief, :id) ||
        Map.get(state.belief, "id")

    if is_nil(belief_id) or is_nil(state.agent_id) do
      []
    else
      Lincoln.Beliefs.BeliefRelationship
      |> where(
        [r],
        r.agent_id == ^state.agent_id and
          (r.source_belief_id == ^belief_id or r.target_belief_id == ^belief_id)
      )
      |> preload([:source_belief, :target_belief])
      |> Lincoln.Repo.all()
      |> Enum.flat_map(&active_related_belief(&1, belief_id))
      |> Enum.take(3)
    end
  end

  defp spawn_exploration_children(candidates, state) do
    # Subscribe BEFORE spawning any children to avoid race condition:
    # local-tier children complete instantly in handle_continue and broadcast
    # before the parent would subscribe, causing the parent to miss messages.
    Phoenix.PubSub.subscribe(
      Lincoln.PubSub,
      PubSubBroadcaster.thought_topic(state.agent_id)
    )

    Enum.reduce(candidates, state, fn {belief, score}, acc ->
      case do_spawn_child(belief, score, acc) do
        {:ok, _child_id, new_acc} -> new_acc
        {:error, _reason} -> acc
      end
    end)
  end

  defp do_spawn_child(belief, score, state) do
    child_id = Ecto.UUID.generate()

    child_opts = %{
      id: child_id,
      agent_id: state.agent_id,
      belief: belief,
      attention_score: score,
      parent_id: state.id
    }

    case ThoughtSupervisor.spawn_thought(state.agent_id, child_opts) do
      {:ok, _pid} ->
        pending = Map.put(state.pending_children, child_id, nil)
        new_state = %{state | pending_children: pending, status: :awaiting_children}
        {:ok, child_id, new_state}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp active_related_belief(rel, belief_id) do
    related = related_belief_from(rel, belief_id)

    if related && related.status == "active" do
      [{related, 0.2}]
    else
      []
    end
  end

  defp related_belief_from(rel, belief_id) do
    cond do
      to_string(rel.source_belief_id) == to_string(belief_id) -> rel.target_belief
      to_string(rel.target_belief_id) == to_string(belief_id) -> rel.source_belief
      true -> nil
    end
  end

  defp finalize(state) do
    PubSubBroadcaster.broadcast_thought_event(
      state.agent_id,
      {:thought_completed, state.id, state.result}
    )

    if state.result && state.result != "Skipped (budget constraint)" do
      store_reflection(state.agent_id, state.belief, state.result)
    end

    Logger.debug("[Thought #{state.id}] Completed: #{state.tier}")
  end

  defp store_reflection(agent_id, belief, text) do
    Task.start(fn ->
      try do
        agent = Agents.get_agent!(agent_id)

        Lincoln.Memory.create_memory(agent, %{
          content: "Reflection on '#{get_statement(belief)}': #{text}",
          memory_type: "reflection",
          importance: 5
        })
      rescue
        e -> Logger.warning("[Thought] Memory store failed: #{Exception.message(e)}")
      end
    end)
  end

  defp get_statement(belief) when is_map(belief) do
    Map.get(belief, :statement) || Map.get(belief, "statement") || inspect(belief)
  end

  defp get_confidence(belief) when is_map(belief) do
    Map.get(belief, :confidence) || Map.get(belief, "confidence") || 0.5
  end
end
