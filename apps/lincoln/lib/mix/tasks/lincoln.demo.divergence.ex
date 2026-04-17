defmodule Mix.Tasks.Lincoln.Demo.Divergence do
  @moduledoc """
  Sets up and runs the Lincoln divergence demo.

  Creates two agents with different attention parameters (Focused vs Butterfly),
  seeds them with the same beliefs, and runs both substrates for N minutes
  while broadcasting the same input events to both.

  ## Options
    * `--minutes` - How long to run the demo (default: 2)

  ## Usage
      mix lincoln.demo.divergence
      mix lincoln.demo.divergence --minutes 5
  """
  use Mix.Task

  alias Lincoln.Agents
  alias Lincoln.Agents.Agent
  alias Lincoln.Beliefs
  alias Lincoln.Substrate
  alias Lincoln.Substrate.{AttentionParams, InputBroadcaster, Trajectory}

  @shortdoc "Run the Lincoln divergence demo with two agents"

  @seed_events [
    %{type: :observation, content: "Elixir's actor model enables massive concurrency"},
    %{type: :question, content: "How does the BEAM handle process scheduling?"},
    %{type: :observation, content: "OTP supervision trees provide fault tolerance"},
    %{type: :question, content: "What distinguishes Lincoln from other AI systems?"},
    %{type: :reflection, content: "Continuity of process is the key architectural property"}
  ]

  @seed_beliefs [
    {"The BEAM VM is optimized for concurrent, distributed systems", "observation", 0.9},
    {"Elixir uses the actor model for concurrency", "training", 0.85},
    {"Continuity of process is fundamental to cognition", "inference", 0.7},
    {"Attention has parameters that create cognitive style", "inference", 0.75},
    {"Memory and cognition are views of the same substrate", "inference", 0.65}
  ]

  @impl Mix.Task
  def run(args) do
    {opts, _, _} = OptionParser.parse(args, strict: [minutes: :integer])
    minutes = Keyword.get(opts, :minutes, 2)

    Mix.Task.run("app.start")

    Mix.shell().info("=== Lincoln Divergence Demo ===\n")
    Mix.shell().info("Running for #{minutes} minute(s)...\n")

    {agent_focused, agent_butterfly} = setup_agents()

    seed_beliefs(agent_focused)
    seed_beliefs(agent_butterfly)

    start_substrates(agent_focused, agent_butterfly)
    broadcast_seed_events(agent_focused, agent_butterfly)

    Mix.shell().info("Watch live at: http://localhost:4000/substrate/compare\n")
    Mix.shell().info("Running for #{minutes} minute(s)... (Ctrl+C to stop early)\n")

    Process.sleep(minutes * 60_000)

    Mix.shell().info("\n=== DIVERGENCE REPORT ===\n")
    print_trajectory(agent_focused, "Focused")
    Mix.shell().info("")
    print_trajectory(agent_butterfly, "Butterfly")

    Substrate.stop_agent(agent_focused.id)
    Substrate.stop_agent(agent_butterfly.id)

    Mix.shell().info("\nDemo complete. View the comparison at /substrate/compare")
  end

  defp setup_agents do
    focused_params = AttentionParams.focused()
    butterfly_params = AttentionParams.butterfly()

    agent_focused = get_or_create_agent("Lincoln-Focused", focused_params)
    agent_butterfly = get_or_create_agent("Lincoln-Butterfly", butterfly_params)

    Mix.shell().info("Agent A: #{agent_focused.name} (Focused params)")

    Mix.shell().info(
      "  novelty_weight=#{focused_params.novelty_weight}, focus_momentum=#{focused_params.focus_momentum}"
    )

    Mix.shell().info("Agent B: #{agent_butterfly.name} (Butterfly params)")

    Mix.shell().info(
      "  novelty_weight=#{butterfly_params.novelty_weight}, focus_momentum=#{butterfly_params.focus_momentum}\n"
    )

    {agent_focused, agent_butterfly}
  end

  defp get_or_create_agent(name, attention_params) do
    case Agents.get_agent_by_name(name) do
      %Agent{} = agent ->
        {:ok, agent} = Agents.update_agent(agent, %{attention_params: attention_params})
        agent

      nil ->
        {:ok, agent} =
          Agents.create_agent(%{
            name: name,
            description: "Demo agent for divergence experiment",
            attention_params: attention_params
          })

        agent
    end
  end

  defp seed_beliefs(agent) do
    existing = Beliefs.list_beliefs(agent, limit: 1)

    if existing == [] do
      Enum.each(@seed_beliefs, fn {statement, source_type, confidence} ->
        Beliefs.create_belief(agent, %{
          statement: statement,
          source_type: source_type,
          confidence: confidence,
          entrenchment: 3
        })
      end)

      Mix.shell().info("Seeded #{length(@seed_beliefs)} beliefs for #{agent.name}")
    else
      Mix.shell().info("#{agent.name} already has beliefs, skipping seed")
    end
  end

  defp start_substrates(agent_focused, agent_butterfly) do
    Mix.shell().info("Starting cognitive substrates...")

    start_one(agent_focused)
    start_one(agent_butterfly)

    Mix.shell().info("Both substrates running\n")
  end

  defp start_one(agent) do
    case Substrate.start_agent(agent.id) do
      {:ok, _pid} -> :ok
      {:error, :already_started} -> :ok
    end
  end

  defp broadcast_seed_events(agent_focused, agent_butterfly) do
    group = [agent_focused.id, agent_butterfly.id]

    Mix.shell().info("Broadcasting #{length(@seed_events)} seed events to both agents...")

    Enum.each(@seed_events, fn event ->
      InputBroadcaster.broadcast_to_group(group, event)
    end)

    Mix.shell().info("Events broadcast\n")
  end

  defp print_trajectory(agent, label) do
    summary = Trajectory.summary(agent.id, hours: 1)
    recent_ticks = Trajectory.get_recent_ticks(agent.id, limit: 5)

    Mix.shell().info("--- #{label} (#{agent.name}) ---")
    Mix.shell().info("  Total substrate events: #{summary.total_events}")
    Mix.shell().info("  Tier distribution: #{inspect(summary.tier_distribution)}")

    recent_ticks
    |> Enum.map(&Trajectory.scoring_detail/1)
    |> Enum.reject(&is_nil/1)
    |> Enum.each(&print_tick_detail/1)
  end

  defp print_tick_detail(detail) do
    top = List.first(detail["top_candidates"] || [])
    if top, do: print_candidate(top)
  end

  defp print_candidate(candidate) do
    components = candidate["components"] || %{}

    Mix.shell().info(
      "  Focus: #{candidate["statement"] || "?"} " <>
        "(score #{format_float(components["final_score"])})"
    )

    Mix.shell().info(
      "    N=#{format_float(components["novelty"])} " <>
        "T=#{format_float(components["tension"])} " <>
        "S=#{format_float(components["staleness"])} " <>
        "D=#{format_float(components["depth"])} " <>
        "focus=#{format_float(components["focus_boost"])}"
    )
  end

  defp format_float(nil), do: "—"
  defp format_float(f) when is_float(f), do: :erlang.float_to_binary(f, decimals: 2)
  defp format_float(f), do: inspect(f)
end
