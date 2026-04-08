defmodule Lincoln.Repo.Migrations.CreateBenchmarks do
  use Ecto.Migration

  def change do
    create table(:benchmark_runs, primary_key: false) do
      add(:id, :binary_id, primary_key: true, default: fragment("gen_random_uuid()"))
      add(:agent_id, references(:agents, type: :binary_id, on_delete: :delete_all), null: false)
      add(:domain, :string, default: "contradiction_detection")
      add(:status, :string, default: "running")
      add(:started_at, :utc_datetime)
      add(:ended_at, :utc_datetime)
      add(:total_tasks, :integer, default: 0)
      add(:correct_tasks, :integer, default: 0)
      add(:notes, :text)
      timestamps(type: :utc_datetime)
    end

    create table(:benchmark_results, primary_key: false) do
      add(:id, :binary_id, primary_key: true, default: fragment("gen_random_uuid()"))

      add(:run_id, references(:benchmark_runs, type: :binary_id, on_delete: :delete_all),
        null: false
      )

      add(:task_id, :string)
      add(:task_data, :map)
      add(:expected, :string)
      add(:got, :string)
      add(:correct, :boolean)
      add(:tier_used, :string)
      add(:latency_ms, :integer)
      add(:evaluated_at, :utc_datetime)
      timestamps(type: :utc_datetime)
    end

    create(index(:benchmark_runs, [:agent_id]))
    create(index(:benchmark_results, [:run_id]))
  end
end
