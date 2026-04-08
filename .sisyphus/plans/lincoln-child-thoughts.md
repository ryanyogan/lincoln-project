# Lincoln: Child Thoughts — Tree-of-Thought as Process Tree (Step 3)

## TL;DR

> **Quick Summary**: When a Level 1/2 Thought executes, it first spawns Level 0 child Thoughts for related beliefs. The parent waits for all children to complete (via PubSub + pending_children tracking), collects their results, then feeds those results into its own LLM call for synthesis. This is real concurrent Tree-of-Thought — each branch is a supervised OTP process, the parent genuinely blocks on all branches, and Python's async cannot produce this supervision structure.
>
> **Deliverables**:
> - `pending_children` + `:awaiting_children` status in Thought struct
> - `Thought.spawn_child/3` — spawns a child under ThoughtSupervisor with parent_id set
> - LLM execution path updated: check for related beliefs → spawn children → await → synthesize
> - Dashboard shows parent-child indentation and tree structure
> - `Thoughts.list_tree/1` — hierarchical thought listing
>
> **Estimated Effort**: Medium (2-3 days)
> **Parallel Execution**: YES — 3 waves
> **Critical Path**: Child state in Thought → LLM path wiring → Dashboard tree view

---

## Context

### Why This Matters
The master plan: *"Sub-thoughts are real child processes, not nested LLM calls in a Python loop. Tree-of-thought is a tree of processes, supervised by OTP, with all the lifecycle management you get for free."*

Sophia's tree-of-thought is "spawn multiple LLM workers" in a Python loop — concurrent coroutines in a single thread. Lincoln's tree-of-thought is concurrent OTP processes where the parent genuinely waits for all children via the BEAM's message-passing primitives.

### Architecture Choice
Children are supervised by the **same ThoughtSupervisor** (flat structure), not by the parent. The parent tracks children via:
1. PubSub subscription to the thought topic
2. `pending_children` map `{child_id => nil | result}`
3. When all values non-nil → synthesize → finalize

This is simpler than making the parent a Supervisor, and the tree structure is visible via `parent_id` in each child's state.

### When Children Are Spawned
Only Level 1/2 thoughts (Ollama/Claude) spawn children. The trigger: the belief has typed relationships in `belief_relationships` (supports/contradicts/related edges). Each related belief becomes a Level 0 child thought for fast parallel exploration.

Pattern:
```
Parent (level 1, belief: "BEAM handles concurrency")
├── Child 0 (level 0, belief: "Elixir uses the actor model")
├── Child 0 (level 0, belief: "OTP supervision provides fault tolerance")
└── Child 0 (level 0, belief: "Erlang was designed for telecom systems")

Parent waits → collects 3 local reflections → synthesizes via Ollama → finalizes
```

---

## TODOs

- [x] 1. Add Child State and Spawning to Thought GenServer

  **What to do**:
  Add `pending_children` to defstruct and implement the full child-tracking flow.

  **Struct changes** — add two fields after `:parent_id`:
  ```elixir
  :pending_children,  # map of child_id => nil | result — nil means still running
  :child_results      # list of completed child results (for synthesis context)
  ```
  Initialize in `init/1`: `pending_children: %{}, child_results: []`

  **Public API** — add after `interrupt/1`:
  ```elixir
  @doc """
  Spawn a child thought under this parent. The child runs under the same
  ThoughtSupervisor with parent_id set to this thought's id.
  """
  def spawn_child(parent_pid, belief, score) do
    GenServer.call(parent_pid, {:spawn_child, belief, score})
  end
  ```

  **handle_call({:spawn_child})** — MUST go before handle_call(:get_state):
  ```elixir
  @impl true
  def handle_call({:spawn_child, belief, score}, _from, state) do
    child_opts = %{
      agent_id: state.agent_id,
      belief: belief,
      attention_score: score,
      parent_id: state.id
    }

    case Lincoln.Substrate.ThoughtSupervisor.spawn_thought(state.agent_id, child_opts) do
      {:ok, _pid} ->
        # Generate what will be the child's ID — we'll get it from the spawned broadcast
        # Instead: subscribe to the thought topic if not already subscribed
        # The child will broadcast {:thought_spawned, child_id, ...} and we track it
        # But we need to know the child_id upfront to add to pending_children
        # Solution: generate the child_id here and pass it in opts

        # REVISED: pass a pre-generated id in child_opts
        # The spawned Thought will use it (we need to change init to accept :id)
        {:reply, :ok, state}

      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end
  ```

  **IMPORTANT DESIGN FIX**: To track children by ID, we need to generate the child ID BEFORE spawning and pass it in opts. Change `init/1` to use `Map.get(opts, :id)` if provided, only generate if not:

  ```elixir
  def init(%{agent_id: agent_id, belief: belief, attention_score: score} = opts) do
    id = Map.get(opts, :id) || Ecto.UUID.generate()  # use provided ID or generate
    ...
  ```

  Then in `handle_call({:spawn_child})`:
  ```elixir
  def handle_call({:spawn_child, belief, score}, _from, state) do
    child_id = Ecto.UUID.generate()
    child_opts = %{
      id: child_id,
      agent_id: state.agent_id,
      belief: belief,
      attention_score: score,
      parent_id: state.id
    }

    case Lincoln.Substrate.ThoughtSupervisor.spawn_thought(state.agent_id, child_opts) do
      {:ok, _pid} ->
        pending = Map.put(state.pending_children, child_id, nil)
        {:reply, {:ok, child_id}, %{state | pending_children: pending}}

      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end
  ```

  **Subscribe to thought topic in init** (to receive child completion events):
  In `init/1`, after building the state, add:
  ```elixir
  # Subscribe to receive child thought completion events
  if Map.get(opts, :parent_id) == nil do
    # Only top-level thoughts (no parent) need to subscribe — they spawn children
    # Actually subscribe always to keep it simple; filter by child_id in handle_info
    Phoenix.PubSub.subscribe(Lincoln.PubSub, Lincoln.PubSubBroadcaster.thought_topic(agent_id))
  end
  ```
  
  Actually: subscribe ONLY when we know we'll spawn children. Add subscription in `handle_call({:spawn_child})` — subscribe once when first child is spawned.

  **Revised `handle_call({:spawn_child})`:**
  ```elixir
  def handle_call({:spawn_child, belief, score}, _from, state) do
    child_id = Ecto.UUID.generate()
    child_opts = %{
      id: child_id,
      agent_id: state.agent_id,
      belief: belief,
      attention_score: score,
      parent_id: state.id
    }

    case Lincoln.Substrate.ThoughtSupervisor.spawn_thought(state.agent_id, child_opts) do
      {:ok, _pid} ->
        # Subscribe to thought topic on first child spawn
        if map_size(state.pending_children) == 0 do
          Phoenix.PubSub.subscribe(
            Lincoln.PubSub,
            Lincoln.PubSubBroadcaster.thought_topic(state.agent_id)
          )
        end
        pending = Map.put(state.pending_children, child_id, nil)
        {:reply, {:ok, child_id}, %{state | pending_children: pending, status: :awaiting_children}}

      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end
  ```

  **Add `:thought_completed` child tracking in `handle_info`** — BEFORE the existing `{ref, result}` handler:
  ```elixir
  # Receive child thought completion — only if we're tracking this child
  def handle_info({:thought_completed, child_id, result}, state)
      when is_map_key(state.pending_children, child_id) do
    pending = Map.put(state.pending_children, child_id, result)
    child_results = [result | state.child_results]
    new_state = %{state | pending_children: pending, child_results: child_results}

    # Check if all children are done
    if Enum.all?(pending, fn {_id, r} -> r != nil end) do
      # All children complete — run LLM synthesis with child context
      Logger.debug("[Thought #{state.id}] All #{map_size(pending)} children done, synthesizing")
      _task = Task.async(fn -> run_llm_with_children(state.belief, state.tier, child_results) end)
      {:noreply, %{new_state | status: :awaiting_llm}}
    else
      remaining = Enum.count(pending, fn {_id, r} -> r == nil end)
      Logger.debug("[Thought #{state.id}] #{remaining} children still pending")
      {:noreply, new_state}
    end
  end

  # Non-child thought_completed events — ignore
  def handle_info({:thought_completed, _other_id, _result}, state), do: {:noreply, state}
  ```

  **Add `run_llm_with_children/3` private helper**:
  ```elixir
  defp run_llm_with_children(belief, tier, child_results) do
    statement = get_statement(belief)
    child_context = child_results
      |> Enum.with_index(1)
      |> Enum.map(fn {result, i} -> "#{i}. #{result}" end)
      |> Enum.join("\n")

    messages = [
      %{role: "system", content: "You are synthesizing insights from parallel explorations. Be concise (3-4 sentences)."},
      %{role: "user", content: """
        Main belief: #{statement}

        Parallel explorations found:
        #{child_context}

        Synthesize these into a coherent reflection on the main belief.
        """}
    ]

    InferenceTier.execute_at_tier(tier, messages, [])
  end
  ```

  **Acceptance Criteria**:
  - [ ] `Thought.spawn_child(parent_pid, belief, score)` returns `{:ok, child_id}`
  - [ ] Child thought has `parent_id` set to parent's `id`
  - [ ] Parent transitions to `:awaiting_children` when children spawned
  - [ ] Parent receives `{:thought_completed, child_id, result}` and tracks it
  - [ ] When all children done, parent runs synthesis LLM call
  - [ ] `mix compile --warnings-as-errors` passes

  **Recommended Agent Profile**: `deep`
  **Commit**: `feat(child-thoughts): add child spawning and tracking to Thought GenServer`

- [x] 2. Wire Child Exploration into LLM Execution Path

  **What to do**:
  Update `handle_continue(:execute)` in `thought.ex` for LLM-tier thoughts to optionally spawn children before running the LLM directly.

  **New execution flow for Level 1/2 thoughts**:
  ```elixir
  @impl true
  def handle_continue(:execute, state) when state.tier in [:ollama, :claude] do
    case find_exploration_candidates(state) do
      [] ->
        # No related beliefs — run LLM directly (existing behavior)
        _task = Task.async(fn -> run_llm(state.belief, state.tier) end)
        {:noreply, %{state | status: :awaiting_llm}}

      candidates ->
        # Spawn children for related beliefs, then wait
        Logger.debug("[Thought #{state.id}] Spawning #{length(candidates)} children for exploration")
        Enum.each(candidates, fn {belief, score} ->
          spawn_child(self(), belief, score)
        end)
        {:noreply, state}  # status set to :awaiting_children by spawn_child
    end
  end
  ```

  **`find_exploration_candidates/1` private function**:
  ```elixir
  defp find_exploration_candidates(state) do
    # Only explore if belief is a real DB belief (has an id)
    belief_id = Map.get(state.belief, :id) || Map.get(state.belief, "id")

    if is_nil(belief_id) or is_nil(state.agent) do
      []
    else
      # Find beliefs related to this one via typed edges
      relationships = Lincoln.Beliefs.find_relationships(state.agent, belief_id)

      relationships
      |> Enum.flat_map(fn rel ->
        # Get the related belief (the one that's NOT the current belief)
        related_belief =
          cond do
            rel.source_belief_id == belief_id -> rel.target_belief
            rel.target_belief_id == belief_id -> rel.source_belief
            true -> nil
          end

        if related_belief && related_belief.status == "active" do
          [{related_belief, 0.2}]  # Level 0 score — local computation only
        else
          []
        end
      end)
      |> Enum.take(3)  # Max 3 children per thought
    end
  end
  ```

  **Note**: `find_relationships/2` must preload source_belief and target_belief. Check the current implementation in `beliefs.ex` — if it doesn't preload, add preloads.

  **Acceptance Criteria**:
  - [ ] LLM-tier thought with related beliefs spawns children and waits
  - [ ] LLM-tier thought with no related beliefs runs LLM directly (unchanged)
  - [ ] Local thoughts NEVER spawn children (unchanged)
  - [ ] Max 3 children per thought
  - [ ] `mix compile --warnings-as-errors` passes

  **Recommended Agent Profile**: `deep`
  **Commit**: `feat(child-thoughts): wire child exploration into LLM execution path`

- [x] 3. Dashboard Tree View + Thoughts.list_tree/1

  **What to do**:
  Update the dashboard and public API to show parent-child structure.

  **`Thoughts.list_tree/1`** in `thoughts.ex`:
  ```elixir
  @doc "Returns thoughts organized as a tree with children nested under parents."
  def list_tree(agent_id) when is_binary(agent_id) do
    all_thoughts = list(agent_id)

    # Separate roots and children
    {roots, children} = Enum.split_with(all_thoughts, fn t -> is_nil(t.parent_id) end)

    # Attach children to their parents
    children_by_parent = Enum.group_by(children, & &1.parent_id)

    Enum.map(roots, fn root ->
      %{thought: root, children: Map.get(children_by_parent, root.id, [])}
    end)
  end
  ```

  **Dashboard update** (`SubstrateThoughtsLive`):
  In the active thoughts display, show children indented under parents:

  ```elixir
  # In mount, use list_tree instead of list
  active_tree = Thoughts.list_tree(agent.id)
  |> assign(:active_tree, active_tree)
  ```

  Template change — render tree structure:
  ```heex
  <%= for %{thought: parent, children: children} <- @active_tree do %>
    <%# Parent thought %>
    <div class="border border-primary/20 rounded p-3 bg-primary/5">
      ...parent display...
    </div>
    <%# Children indented %>
    <%= for child <- children do %>
      <div class="border border-base-content/10 rounded p-2 bg-base-200/30 ml-4 border-l-2 border-l-info/30">
        ...child display...
      </div>
    <% end %>
  <% end %>
  ```

  **Acceptance Criteria**:
  - [ ] `Thoughts.list_tree/1` returns hierarchical structure
  - [ ] Dashboard shows children indented under parents
  - [ ] Dashboard still updates live via PubSub (handle_info for spawned/completed/interrupted)
  - [ ] `mix compile --warnings-as-errors` passes

  **Recommended Agent Profile**: `visual-engineering`
  **Skills**: `["frontend-ui-ux"]`
  **Commit**: `feat(child-thoughts): add tree view to Thoughts API and dashboard`

---

## Final Verification

- [ ] F1. `mix compile --warnings-as-errors` — zero warnings
- [ ] F2. Manual: start substrate with related beliefs → observe parent spawning children in `/substrate/thoughts`
- [ ] F3. Confirm children complete before parent synthesizes

---

## The Demo After Step 3

```
/substrate/thoughts — live view showing:

ACTIVE
▶ Contemplating: "The BEAM handles concurrency via actor model"  [L1] [awaiting_children]
  ├── "Elixir uses processes as actors"                          [L0] [executing]
  ├── "OTP provides supervision for fault tolerance"              [L0] [completed]
  └── "Erlang was built for telecom systems"                      [L0] [completed]

→ When all 3 children complete → parent runs synthesis → "completed"
```

This is something nobody has seen in an AI agent system. Thoughts spawning sub-thoughts. Processes waiting for processes. The BEAM doing what it was built to do.
