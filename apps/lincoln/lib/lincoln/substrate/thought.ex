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

  alias Lincoln.{Agents, PubSubBroadcaster}
  alias Lincoln.Substrate.InferenceTier

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
    :parent_id
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

  # ============================================================================
  # GenServer callbacks
  # ============================================================================

  @impl true
  def init(%{agent_id: agent_id, belief: belief, attention_score: score} = opts) do
    id = Ecto.UUID.generate()
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
      parent_id: Map.get(opts, :parent_id)
    }

    belief_statement = get_statement(belief)

    PubSubBroadcaster.broadcast_thought_event(
      agent_id,
      {:thought_spawned, id, belief_statement, tier}
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
  def handle_continue(:execute, state) do
    _task = Task.async(fn -> run_llm(state.belief, state.tier) end)
    {:noreply, %{state | status: :awaiting_llm}}
  end

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
  def handle_call(:get_state, _from, state) do
    {:reply, state, state}
  end

  @impl true
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
