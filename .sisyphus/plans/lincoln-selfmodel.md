# Lincoln: Self-Model (Step 6)

## TL;DR
> A representation of what Lincoln knows about itself — capabilities, limitations, learning trajectory, failure patterns. Built from the supervision tree data (thought success/failure rates, tier distributions, contradiction detection rates). Lets Lincoln say "I tend to get stuck on X" or "I've been improving at Y."
>
> **Deliverables**: `self_model` table + `Lincoln.SelfModel` context + substrate tick update + dashboard widget on `/substrate`
>
> **Estimated Effort**: Small (half day)

---

## TODOs

- [ ] 1. Migration + Schema + Context

  **Generate**: `mix ecto.gen.migration create_self_model`

  Single row per agent (upsert pattern) — one self-model, continuously updated:
  ```elixir
  create table(:self_model, primary_key: false) do
    add :id, :binary_id, primary_key: true, default: fragment("gen_random_uuid()")
    add :agent_id, references(:agents, type: :binary_id, on_delete: :delete_all), null: false
    # Capability metrics — updated from trajectory
    add :total_thoughts, :integer, default: 0
    add :completed_thoughts, :integer, default: 0
    add :failed_thoughts, :integer, default: 0
    add :interrupted_thoughts, :integer, default: 0
    add :local_tier_count, :integer, default: 0
    add :ollama_tier_count, :integer, default: 0
    add :claude_tier_count, :integer, default: 0
    # Inferred traits
    add :dominant_topics, {:array, :string}, default: []
    add :contradiction_detections, :integer, default: 0
    add :cascade_detections, :integer, default: 0
    add :narrative_count, :integer, default: 0
    add :total_ticks, :integer, default: 0
    # Self-knowledge summary (LLM-generated, updated every 500 ticks)
    add :self_summary, :string
    add :last_updated_at, :utc_datetime
    timestamps(type: :utc_datetime)
  end
  create unique_index(:self_model, [:agent_id])
  ```

  **Context** — `lib/lincoln/self_model.ex`:
  - `get_or_create(agent_id)` — upsert
  - `update_from_trajectory(agent_id)` — recomputes metrics from trajectory table + narrative count
  - `get_self_summary(agent_id)` — returns the self_summary string for display

  **Recommended Agent Profile**: `quick`
  **Commit**: `feat(self-model): add self_model table, schema, and context`

- [ ] 2. Substrate update trigger + dashboard widget

  Every 50 ticks, the substrate calls `SelfModel.update_from_trajectory(agent_id)` (async, non-blocking).

  In `/substrate` dashboard (`substrate_live.ex`), add a small "SELF MODEL" panel showing:
  - Success rate: `completed / (completed + failed)`
  - Tier distribution: L0/L1/L2 percentages
  - Total ticks / total thoughts
  - Dominant topics (from trajectory)
  - Self-summary (if generated)

  **Recommended Agent Profile**: `deep`
  **Commit**: `feat(self-model): wire self-model updates and display in substrate dashboard`
