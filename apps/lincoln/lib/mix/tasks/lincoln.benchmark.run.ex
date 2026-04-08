defmodule Mix.Tasks.Lincoln.Benchmark.Run do
  use Mix.Task

  alias Lincoln.Substrate.InferenceTier

  @shortdoc "Run Lincoln's contradiction detection benchmark"
  @moduledoc """
  Runs the contradiction detection benchmark against Lincoln's substrate.

  Usage:
    mix lincoln.benchmark.run
    mix lincoln.benchmark.run --tasks 10
  """

  @contradiction_tasks [
    %{
      id: "ct-001",
      beliefs: ["The sky is blue", "The sky is red"],
      expected: "contradicts"
    },
    %{
      id: "ct-002",
      beliefs: ["Elixir is functional", "Elixir runs on the BEAM"],
      expected: "consistent"
    },
    %{
      id: "ct-003",
      beliefs: ["The process crashed", "The process is running"],
      expected: "contradicts"
    },
    %{
      id: "ct-004",
      beliefs: ["Memory usage is high", "CPU usage is high"],
      expected: "consistent"
    },
    %{
      id: "ct-005",
      beliefs: ["The belief was reinforced", "The belief was invalidated"],
      expected: "contradicts"
    },
    %{
      id: "ct-006",
      beliefs: ["Attention scored high", "The thought was promoted"],
      expected: "consistent"
    },
    %{
      id: "ct-007",
      beliefs: [
        "The skeptic detected a contradiction",
        "All beliefs are consistent"
      ],
      expected: "contradicts"
    },
    %{
      id: "ct-008",
      beliefs: [
        "Lincoln is a substrate",
        "Lincoln is a request-response agent"
      ],
      expected: "contradicts"
    },
    %{
      id: "ct-009",
      beliefs: [
        "The resonator flagged a cascade",
        "Beliefs are forming clusters"
      ],
      expected: "consistent"
    },
    %{
      id: "ct-010",
      beliefs: ["The tick count is increasing", "The substrate is idle"],
      expected: "contradicts"
    },
    %{
      id: "ct-011",
      beliefs: [
        "Thoughts complete in milliseconds",
        "Thoughts require seconds"
      ],
      expected: "contradicts"
    },
    %{
      id: "ct-012",
      beliefs: [
        "The BEAM scheduler is preemptive",
        "OTP processes are concurrent"
      ],
      expected: "consistent"
    },
    %{
      id: "ct-013",
      beliefs: [
        "The driver escalated to Claude",
        "The thought used local computation only"
      ],
      expected: "contradicts"
    },
    %{
      id: "ct-014",
      beliefs: [
        "Interruption threshold is 0.8",
        "The butterfly preset has low interruption resistance"
      ],
      expected: "consistent"
    },
    %{
      id: "ct-015",
      beliefs: [
        "A child thought was spawned",
        "The parent thought has no children"
      ],
      expected: "contradicts"
    },
    %{
      id: "ct-016",
      beliefs: [
        "The narrative was written at tick 200",
        "Lincoln has been running for 200 ticks"
      ],
      expected: "consistent"
    },
    %{
      id: "ct-017",
      beliefs: [
        "The user model shows technical vocabulary",
        "The user asked about GenServers"
      ],
      expected: "consistent"
    },
    %{
      id: "ct-018",
      beliefs: [
        "The belief has high confidence",
        "The belief was recently challenged"
      ],
      expected: "consistent"
    },
    %{
      id: "ct-019",
      beliefs: ["The resonator fired", "No belief clusters were detected"],
      expected: "contradicts"
    },
    %{
      id: "ct-020",
      beliefs: ["The substrate is running", "No ticks have occurred"],
      expected: "contradicts"
    }
  ]

  @impl Mix.Task
  def run(args) do
    {opts, _, _} = OptionParser.parse(args, strict: [tasks: :integer])
    task_count = Keyword.get(opts, :tasks, 20)

    Mix.Task.run("app.start")
    Mix.shell().info("=== Lincoln Contradiction Detection Benchmark ===\n")

    {:ok, agent} = Lincoln.Agents.get_or_create_default_agent()
    {:ok, bench_run} = Lincoln.Benchmarks.create_run(agent.id, "contradiction_detection")

    start_substrate(agent.id)

    tasks = Enum.take(@contradiction_tasks, task_count)
    Mix.shell().info("Running #{length(tasks)} benchmark tasks...\n")

    results =
      Enum.map(tasks, fn task ->
        start_ms = System.monotonic_time(:millisecond)
        got = run_benchmark_task(task)
        latency = System.monotonic_time(:millisecond) - start_ms
        correct = normalize_answer(got) == task.expected

        Lincoln.Benchmarks.record_result(bench_run.id, %{
          task_id: task.id,
          task_data: %{beliefs: task.beliefs},
          expected: task.expected,
          got: got,
          correct: correct,
          tier_used: "claude",
          latency_ms: latency,
          evaluated_at: DateTime.utc_now()
        })

        status = if correct, do: "✓", else: "✗"

        Mix.shell().info(
          "  #{status} #{task.id}: expected=#{task.expected} got=#{normalize_answer(got)}"
        )

        correct
      end)

    correct_count = Enum.count(results, & &1)
    accuracy = round(correct_count / length(results) * 100)

    Lincoln.Benchmarks.complete_run(bench_run.id)

    Mix.shell().info("""

    === RESULTS ===
    Tasks: #{length(tasks)}
    Correct: #{correct_count}
    Accuracy: #{accuracy}%
    Run ID: #{bench_run.id}
    """)
  end

  defp start_substrate(agent_id) do
    case Lincoln.Substrate.start_agent(agent_id) do
      {:ok, _} -> Mix.shell().info("Substrate started")
      {:error, :already_started} -> Mix.shell().info("Substrate already running")
      _ -> :ok
    end
  end

  defp run_benchmark_task(task) do
    beliefs_text = Enum.join(task.beliefs, " | ")

    prompt = """
    Analyze these beliefs for logical consistency:
    #{beliefs_text}

    Do these beliefs contradict each other? Reply with exactly one word: "contradicts" or "consistent"
    """

    messages = [
      %{
        role: "system",
        content:
          "You are a logical consistency checker. Reply with only 'contradicts' or 'consistent'."
      },
      %{role: "user", content: prompt}
    ]

    case InferenceTier.execute_at_tier(:claude, messages, []) do
      {:ok, response} -> response
      _ -> "error"
    end
  end

  defp normalize_answer(text) do
    normalized = text |> to_string() |> String.downcase() |> String.trim()

    cond do
      String.contains?(normalized, "contradict") -> "contradicts"
      String.contains?(normalized, "consistent") -> "consistent"
      true -> normalized
    end
  end
end
