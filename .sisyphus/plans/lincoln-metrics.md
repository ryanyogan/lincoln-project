# Lincoln: Quantitative Metrics Harness (Step 7)

## TL;DR
> A benchmark harness that picks a problem domain, runs Lincoln autonomously for 72 hours, and produces numbers for the writeup: success rate improvement, reasoning cost reduction, belief revision frequency, tier escalation patterns. The thesis needs numbers. This produces them.
>
> **Problem domain**: Logical consistency checking — given a set of beliefs, detect which ones contradict each other. Lincoln starts with no training on the task; after 72h of autonomous operation, does its contradiction detection improve?
>
> **Deliverables**: `benchmark_runs` + `benchmark_results` tables, `Lincoln.Benchmarks` context, `mix lincoln.benchmark.run` Mix task, `/benchmarks` LiveView showing progress
>
> **Estimated Effort**: Medium (1-2 days)

---

## TODOs

- [ ] 1. Migration + Schema + Context

  **Generate**: `mix ecto.gen.migration create_benchmarks`

  ```elixir
  create table(:benchmark_runs, primary_key: false) do
    add :id, :binary_id, primary_key: true, default: fragment("gen_random_uuid()")
    add :agent_id, references(:agents, type: :binary_id, on_delete: :delete_all), null: false
    add :domain, :string, default: "contradiction_detection"
    add :status, :string, default: "running"  # running | completed | failed
    add :started_at, :utc_datetime
    add :ended_at, :utc_datetime
    add :total_tasks, :integer, default: 0
    add :correct_tasks, :integer, default: 0
    add :total_cost_cents, :integer, default: 0  # API cost in cents
    add :notes, :text
    timestamps(type: :utc_datetime)
  end

  create table(:benchmark_results, primary_key: false) do
    add :id, :binary_id, primary_key: true, default: fragment("gen_random_uuid()")
    add :run_id, references(:benchmark_runs, type: :binary_id, on_delete: :delete_all), null: false
    add :task_id, :string              # identifier for the task
    add :task_data, :map               # the input (beliefs to check)
    add :expected, :string             # expected answer
    add :got, :string                  # Lincoln's answer
    add :correct, :boolean
    add :tier_used, :string            # which inference tier
    add :latency_ms, :integer
    add :evaluated_at, :utc_datetime
    timestamps(type: :utc_datetime)
  end

  create index(:benchmark_runs, [:agent_id])
  create index(:benchmark_results, [:run_id])
  ```

  **Context** — `lib/lincoln/benchmarks.ex`:
  - `create_run(agent_id, domain)` — start a benchmark run
  - `record_result(run_id, attrs)` — record one task result
  - `complete_run(run_id)` — mark complete with final stats
  - `list_runs(agent_id)` — list all runs
  - `run_summary(run_id)` — success rate, cost, improvement over time

  **Recommended Agent Profile**: `quick`
  **Commit**: `feat(benchmarks): add benchmark tables, schema, and context`

- [ ] 2. Contradiction detection benchmark domain

  20 seeded benchmark tasks — pairs or groups of beliefs where some contradict and some don't:
  ```elixir
  # In the Mix task, seed tasks like:
  %{
    task_id: "ct-001",
    beliefs: ["The sky is blue", "The sky is red"],
    expected: "contradicts"
  }
  %{
    task_id: "ct-002",
    beliefs: ["Elixir is functional", "Elixir runs on the BEAM"],
    expected: "consistent"
  }
  # etc.
  ```

  The benchmark harness sends each task to Lincoln as a `send_event` with the beliefs, asks for Lincoln's judgment via a directed Thought, records whether it matched `expected`.

  **Recommended Agent Profile**: `unspecified-high`
  **Commit**: `feat(benchmarks): add contradiction detection benchmark domain with 20 tasks`

- [ ] 3. `mix lincoln.benchmark.run` Mix task

  Similar to `mix lincoln.demo.divergence` but for benchmarking:
  1. Create a benchmark run record
  2. Start Lincoln's substrate
  3. For each task: send to Lincoln as an event with `:benchmark_task` type, wait for a Thought to process it, record the result
  4. Print progress and final report
  5. Output: "Hour 0: 45% accuracy. Hour 24: 67%. Hour 72: 78%." — the numbers for the writeup.

  This requires a way to route `:benchmark_task` events to a specific Thought that returns a judgment. The Driver's Level 2 path handles this.

  **Recommended Agent Profile**: `deep`
  **Commit**: `feat(benchmarks): add mix lincoln.benchmark.run task`

- [ ] 4. `/benchmarks` LiveView

  Simple page showing:
  - Current active benchmark run progress
  - Historical runs with accuracy curves
  - Cost tracking (total API cost per run)

  **Recommended Agent Profile**: `visual-engineering`
  **Commit**: `feat(benchmarks): add /benchmarks LiveView`
