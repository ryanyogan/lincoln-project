defmodule Lincoln.Benchmarks do
  @moduledoc """
  Quantitative performance tracking for Lincoln's cognitive capabilities.

  Supports running benchmark suites (e.g. contradiction detection) and
  recording per-task results for accuracy tracking over time.
  """

  import Ecto.Query

  alias Lincoln.Benchmarks.{BenchmarkResult, BenchmarkRun}
  alias Lincoln.Repo

  def create_run(agent_id, domain) do
    %BenchmarkRun{}
    |> BenchmarkRun.changeset(%{
      agent_id: agent_id,
      domain: domain,
      started_at: DateTime.utc_now()
    })
    |> Repo.insert()
  end

  def record_result(run_id, attrs) do
    %BenchmarkResult{}
    |> BenchmarkResult.changeset(Map.put(attrs, :run_id, run_id))
    |> Repo.insert()
  end

  def complete_run(run_id) do
    run = Repo.get!(BenchmarkRun, run_id) |> Repo.preload(:results)

    total = length(run.results)
    correct = Enum.count(run.results, & &1.correct)

    run
    |> BenchmarkRun.changeset(%{
      status: "completed",
      ended_at: DateTime.utc_now(),
      total_tasks: total,
      correct_tasks: correct
    })
    |> Repo.update()
  end

  def list_runs(agent_id) do
    BenchmarkRun
    |> where([r], r.agent_id == ^agent_id)
    |> order_by([r], desc: r.inserted_at)
    |> Repo.all()
  end

  def get_run(run_id) do
    BenchmarkRun
    |> Repo.get(run_id)
    |> Repo.preload(:results)
  end

  def accuracy(run_id) do
    run = get_run(run_id)

    if run && run.total_tasks > 0 do
      round(run.correct_tasks / run.total_tasks * 100)
    else
      0
    end
  end
end
