defmodule Lincoln.Benchmarks.BenchmarkRun do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "benchmark_runs" do
    field(:domain, :string, default: "contradiction_detection")
    field(:status, :string, default: "running")
    field(:started_at, :utc_datetime)
    field(:ended_at, :utc_datetime)
    field(:total_tasks, :integer, default: 0)
    field(:correct_tasks, :integer, default: 0)
    field(:notes, :string)
    belongs_to(:agent, Lincoln.Agents.Agent)
    has_many(:results, Lincoln.Benchmarks.BenchmarkResult, foreign_key: :run_id)
    timestamps(type: :utc_datetime)
  end

  def changeset(run, attrs) do
    run
    |> cast(attrs, [
      :agent_id,
      :domain,
      :status,
      :started_at,
      :ended_at,
      :total_tasks,
      :correct_tasks,
      :notes
    ])
    |> validate_required([:agent_id])
  end
end
