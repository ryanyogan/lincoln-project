# Lincoln: Narrative Reflections (Step 5)

## TL;DR

> **Quick Summary**: Every 200 substrate ticks, Lincoln spawns a "narrative thought" — a Level 2 (Claude) Thought that generates a short autobiographical passage about what Lincoln has been working on, what it has learned, and how it has changed. These accumulate in a `narrative_reflections` table and become Lincoln's autobiography over time. Critical for the divergence demo: two Lincolns with different parameters will write different autobiographies.
>
> **Deliverables**:
> - `narrative_reflections` table (migration + schema)
> - `Lincoln.Narratives` context: `create_reflection/2`, `list_reflections/2`
> - Substrate tick counter triggers narrative thought every N ticks
> - `/narrative` LiveView showing Lincoln's autobiography as a scrollable feed
>
> **Estimated Effort**: Small (1 day)
> **Parallel Execution**: Mostly sequential

---

## TODOs

- [x] 1. Migration + Schema + Context

  **Generate**: `mix ecto.gen.migration create_narrative_reflections`
  
  ```elixir
  create table(:narrative_reflections, primary_key: false) do
    add :id, :binary_id, primary_key: true, default: fragment("gen_random_uuid()")
    add :agent_id, references(:agents, type: :binary_id, on_delete: :delete_all), null: false
    add :content, :text, null: false          # the autobiographical passage
    add :tick_number, :integer                 # which substrate tick triggered this
    add :period_start_tick, :integer           # what range of ticks this covers
    add :period_end_tick, :integer
    add :belief_count, :integer                # how many beliefs existed at time of writing
    add :thought_count, :integer               # how many thoughts had been spawned
    add :dominant_topics, {:array, :string}, default: []  # from trajectory + user model
    timestamps(type: :utc_datetime)
  end
  create index(:narrative_reflections, [:agent_id])
  create index(:narrative_reflections, [:agent_id, :tick_number])
  ```

  **Schema** — `lib/lincoln/narratives/narrative_reflection.ex`:
  Simple schema with belongs_to Agent, all fields as above.

  **Context** — `lib/lincoln/narratives.ex`:
  ```elixir
  def create_reflection(agent_id, attrs) do
    %NarrativeReflection{}
    |> NarrativeReflection.changeset(Map.put(attrs, :agent_id, agent_id))
    |> Repo.insert()
  end

  def list_reflections(agent_id, opts \\ []) do
    limit = Keyword.get(opts, :limit, 20)
    NarrativeReflection
    |> where([r], r.agent_id == ^agent_id)
    |> order_by([r], desc: r.inserted_at)
    |> limit(^limit)
    |> Repo.all()
  end

  def latest_reflection(agent_id) do
    NarrativeReflection
    |> where([r], r.agent_id == ^agent_id)
    |> order_by([r], desc: r.inserted_at)
    |> limit(1)
    |> Repo.one()
  end
  ```

  **Recommended Agent Profile**: `quick`
  **Commit**: `feat(narrative): add narrative_reflections table, schema, and context`

- [x] 2. Narrative Thought Trigger in Substrate

  Every N ticks (default 200, configurable), spawn a special narrative Thought.

  **In `substrate.ex` `handle_info(:tick)`**, after updating `new_state`, check:
  ```elixir
  # Trigger narrative reflection every @narrative_interval ticks
  if rem(new_state.tick_count, @narrative_interval) == 0 and new_state.tick_count > 0 do
    spawn_narrative_thought(new_state)
  end
  ```

  Add `@narrative_interval 200` module attribute.

  **`spawn_narrative_thought/1` private function**:
  ```elixir
  defp spawn_narrative_thought(state) do
    # Narrative thoughts are special: they reflect on the agent itself
    narrative_belief = %{
      id: nil,  # not a real belief — synthetic
      statement: "Reflect on what I have been thinking about and learning recently",
      confidence: 1.0,
      source_type: "introspection"
    }

    thought_opts = %{
      agent_id: state.agent_id,
      belief: narrative_belief,
      attention_score: 0.9,  # always Level 2 (Claude) — important
      is_narrative: true     # flag for the Thought to handle differently
    }

    case ThoughtSupervisor.spawn_thought(state.agent_id, thought_opts) do
      {:ok, _pid} ->
        Logger.info("[Substrate #{state.agent_id}] Narrative thought spawned at tick #{state.tick_count}")
      {:error, reason} ->
        Logger.debug("[Substrate #{state.agent_id}] Could not spawn narrative thought: #{inspect(reason)}")
    end
  end
  ```

  **In `thought.ex`**: detect `is_narrative: true` in opts and run a different LLM prompt:

  In `init/1`:
  ```elixir
  is_narrative: Map.get(opts, :is_narrative, false)
  ```
  Add `:is_narrative` to defstruct.

  In `handle_continue(:execute)`, add a clause:
  ```elixir
  def handle_continue(:execute, %{is_narrative: true} = state) do
    _task = Task.async(fn -> run_narrative_llm(state) end)
    {:noreply, %{state | status: :awaiting_llm}}
  end
  ```

  **`run_narrative_llm/1`**:
  ```elixir
  defp run_narrative_llm(state) do
    # Gather context: recent trajectory summary, top beliefs, recent memories
    agent = state.agent

    trajectory_summary =
      try do
        Lincoln.Substrate.Trajectory.summary(state.agent_id, hours: 1)
      rescue
        _ -> %{total_events: 0, thought_counts: %{}}
      end

    messages = [
      %{role: "system", content: """
        You are Lincoln's introspective voice. Write a short autobiographical passage
        (3-5 sentences) in first person describing what you have been thinking about,
        what you have learned, and how your understanding has changed recently.
        Be specific about beliefs and topics. Be honest about uncertainties.
        Write as a continuous entity that has been running and thinking.
        """},
      %{role: "user", content: """
        Recent activity summary:
        - Total substrate events in last hour: #{trajectory_summary.total_events}
        - Thoughts completed: #{get_in(trajectory_summary, [:thought_counts, :completed]) || 0}

        Write your reflection.
        """}
    ]

    case InferenceTier.execute_at_tier(:claude, messages, []) do
      {:ok, text} ->
        # Persist the narrative
        Task.start(fn ->
          try do
            Lincoln.Narratives.create_reflection(state.agent_id, %{
              content: text,
              tick_number: 0,
              dominant_topics: []
            })
          rescue
            e -> Logger.warning("[Thought] Narrative persist failed: #{Exception.message(e)}")
          end
        end)
        {:ok, text}
      error -> error
    end
  end
  ```

  **Recommended Agent Profile**: `deep`
  **Commit**: `feat(narrative): trigger narrative reflections every N substrate ticks`

- [x] 3. `/narrative` LiveView — Lincoln's Autobiography

  Simple read-only page showing narrative reflections in reverse chronological order.

  **Route**: `live "/narrative", NarrativeLive, :index`

  **Template**: Clean reading experience — each reflection as a styled block with timestamp and tick number. No real-time updates needed (reflections are infrequent).

  ```heex
  <Layouts.app flash={@flash} current_scope={nil}>
    <div class="container mx-auto max-w-2xl p-4">
      <h1 class="font-terminal text-xl text-primary mb-2">LINCOLN'S AUTOBIOGRAPHY</h1>
      <p class="text-base-content/30 text-xs mb-8">
        Self-generated reflections, every {200} substrate ticks
      </p>

      <%= if @reflections == [] do %>
        <div class="text-center py-16">
          <p class="text-base-content/30 font-terminal">NO REFLECTIONS YET</p>
          <p class="text-base-content/20 text-xs mt-2">
            Lincoln writes after 200 substrate ticks (~16 minutes at 5s/tick)
          </p>
        </div>
      <% else %>
        <div class="space-y-6">
          <%= for reflection <- @reflections do %>
            <div class="border-l-2 border-primary/30 pl-4">
              <div class="font-terminal text-xs text-base-content/30 mb-2">
                {Calendar.strftime(reflection.inserted_at, "%Y-%m-%d %H:%M")}
                · tick #{reflection.tick_number}
              </div>
              <p class="text-base-content/80 leading-relaxed text-sm">
                {reflection.content}
              </p>
            </div>
          <% end %>
        </div>
      <% end %>
    </div>
  </Layouts.app>
  ```

  **Recommended Agent Profile**: `visual-engineering`
  **Commit**: `feat(narrative): add /narrative LiveView for Lincoln's autobiography`

---

## Definition of Done
- [ ] `mix compile --warnings-as-errors` passes
- [ ] Migration exists in `priv/repo/migrations/`
- [ ] `Lincoln.Narratives.create_reflection/2` and `list_reflections/2` exist
- [ ] Substrate spawns narrative thoughts at tick % 200 == 0
- [ ] `/narrative` route loads and shows empty state gracefully
