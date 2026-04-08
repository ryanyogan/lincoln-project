defmodule Lincoln.MCP.Tools do
  @moduledoc false

  require Logger

  alias Lincoln.{Agents, Substrate}
  alias Lincoln.Substrate.Thoughts

  def list_definitions do
    [
      %{
        name: "observe",
        description:
          "Drop an observation into Lincoln's cognitive environment. " <>
            "Lincoln will notice it on the next tick and process it through Attention.",
        inputSchema: %{
          type: "object",
          properties: %{
            content: %{type: "string", description: "The observation to inject"},
            agent_id: %{type: "string", description: "Agent ID (default: default agent)"}
          },
          required: ["content"]
        }
      },
      %{
        name: "get_state",
        description:
          "Get Lincoln's current cognitive state — tick count, focus, " <>
            "attention score, inference tier, running thoughts.",
        inputSchema: %{
          type: "object",
          properties: %{
            agent_id: %{type: "string", description: "Agent ID (default: default agent)"}
          }
        }
      },
      %{
        name: "list_agents",
        description: "List all Lincoln agents and which have active substrates.",
        inputSchema: %{type: "object", properties: %{}}
      },
      %{
        name: "start_substrate",
        description:
          "Start Lincoln's cognitive substrate for an agent. " <>
            "Kicks off the OTP processes that give Lincoln continuous cognition.",
        inputSchema: %{
          type: "object",
          properties: %{
            agent_id: %{type: "string", description: "Agent ID (default: default agent)"}
          }
        }
      },
      %{
        name: "stop_substrate",
        description: "Stop the cognitive substrate for an agent.",
        inputSchema: %{
          type: "object",
          properties: %{
            agent_id: %{type: "string", description: "Agent ID (default: default agent)"}
          }
        }
      }
    ]
  end

  def call("observe", %{"content" => content} = args) do
    with {:ok, agent} <- resolve_agent(args["agent_id"]) do
      event = %{
        type: :observation,
        content: content,
        source: :mcp,
        occurred_at: DateTime.utc_now()
      }

      case Substrate.send_event(agent.id, event) do
        :ok ->
          tool_result("Observation delivered to Lincoln's substrate. Next tick in ~5s.")

        {:error, :not_running} ->
          tool_result("Substrate not running. Use start_substrate first.")
      end
    end
  end

  def call("get_state", args) do
    with {:ok, agent} <- resolve_agent(args["agent_id"]) do
      case Substrate.get_agent_state(agent.id) do
        {:ok, state} ->
          thoughts = Thoughts.list(agent.id)
          self_model = Lincoln.SelfModel.get(agent.id)

          text =
            [
              "Agent: #{agent.name} (#{agent.id})",
              "Tick: #{state.tick_count}",
              "Focus: #{focus_label(state.current_focus)}",
              "Attention score: #{format_float(state.last_attention_score)}",
              "Tier: #{state.last_tier || "none"}",
              "Pending events: #{length(state.pending_events)}",
              "Running thoughts: #{length(thoughts)}",
              format_thoughts(thoughts),
              if(self_model,
                do: "Self-model: #{Lincoln.SelfModel.to_summary_string(self_model)}",
                else: nil
              )
            ]
            |> Enum.reject(&is_nil/1)
            |> Enum.join("\n")

          tool_result(text)

        {:error, :not_running} ->
          tool_result("Substrate not running for #{agent.name}. Use start_substrate.")
      end
    end
  end

  def call("list_agents", _args) do
    agents = Agents.list_agents()
    running = Substrate.list_running_agents()

    lines =
      Enum.map(agents, fn agent ->
        status = if agent.id in running, do: "● RUNNING", else: "○ stopped"
        "#{status}  #{agent.name} (#{agent.id})"
      end)

    text = if lines == [], do: "No agents found.", else: Enum.join(lines, "\n")
    tool_result(text)
  end

  def call("start_substrate", args) do
    with {:ok, agent} <- resolve_agent(args["agent_id"]) do
      case Substrate.start_agent(agent.id) do
        {:ok, _pid} ->
          tool_result("Substrate started for #{agent.name}. Ticking every 5s.")

        {:error, :already_started} ->
          tool_result("Substrate already running for #{agent.name}.")

        {:error, reason} ->
          {:error, "Failed to start: #{inspect(reason)}"}
      end
    end
  end

  def call("stop_substrate", args) do
    with {:ok, agent} <- resolve_agent(args["agent_id"]) do
      case Substrate.stop_agent(agent.id) do
        :ok -> tool_result("Substrate stopped for #{agent.name}.")
        {:error, :not_running} -> tool_result("Substrate was not running for #{agent.name}.")
        {:error, reason} -> {:error, "Failed to stop: #{inspect(reason)}"}
      end
    end
  end

  def call(name, _args), do: {:error, "Unknown tool: #{name}"}

  defp tool_result(text) do
    {:ok, %{content: [%{type: "text", text: text}]}}
  end

  defp resolve_agent(nil), do: Agents.get_or_create_default_agent()

  defp resolve_agent(agent_id) do
    case Agents.get_agent(agent_id) do
      nil -> {:error, "Agent #{agent_id} not found"}
      agent -> {:ok, agent}
    end
  end

  defp focus_label(nil), do: "None"

  defp focus_label(belief) do
    statement = Map.get(belief, :statement, "unknown")
    confidence = Map.get(belief, :confidence, 0) |> Float.round(2)
    "\"#{statement}\" (confidence: #{confidence})"
  end

  defp format_float(nil), do: "N/A"
  defp format_float(f), do: f |> Float.round(3) |> to_string()

  defp format_thoughts([]), do: nil

  defp format_thoughts(thoughts) do
    lines =
      Enum.map(thoughts, fn t ->
        belief = Map.get(t, :belief) || %{}
        stmt = Map.get(belief, :statement) || "unknown"
        "  → [#{t.tier}] #{stmt} (#{t.status})"
      end)

    "Active thoughts:\n" <> Enum.join(lines, "\n")
  end
end
