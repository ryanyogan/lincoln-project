defmodule Lincoln.Benchmarks.BenchmarkResult do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "benchmark_results" do
    field(:task_id, :string)
    field(:task_data, :map)
    field(:expected, :string)
    field(:got, :string)
    field(:correct, :boolean)
    field(:tier_used, :string)
    field(:latency_ms, :integer)
    field(:evaluated_at, :utc_datetime)
    belongs_to(:run, Lincoln.Benchmarks.BenchmarkRun)
    timestamps(type: :utc_datetime)
  end

  def changeset(result, attrs) do
    result
    |> cast(attrs, [
      :run_id,
      :task_id,
      :task_data,
      :expected,
      :got,
      :correct,
      :tier_used,
      :latency_ms,
      :evaluated_at
    ])
    |> validate_required([:run_id])
  end
end
