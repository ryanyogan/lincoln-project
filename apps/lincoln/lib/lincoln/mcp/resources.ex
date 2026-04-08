defmodule Lincoln.MCP.Resources do
  @moduledoc false

  alias Lincoln.{Agents, Beliefs, Memory, Narratives}
  alias Lincoln.Substrate
  alias Lincoln.Substrate.Thoughts

  def list_definitions do
    [
      %{
        uri: "lincoln://state",
        name: "state",
        mimeType: "text/plain",
        description: "Lincoln's current cognitive state"
      },
      %{
        uri: "lincoln://beliefs",
        name: "beliefs",
        mimeType: "application/json",
        description: "Lincoln's active beliefs with confidence scores"
      },
      %{
        uri: "lincoln://thoughts",
        name: "thoughts",
        mimeType: "application/json",
        description: "Currently running Thought processes"
      },
      %{
        uri: "lincoln://memories",
        name: "memories",
        mimeType: "application/json",
        description: "Lincoln's recent memories"
      },
      %{
        uri: "lincoln://narrative",
        name: "narrative",
        mimeType: "text/plain",
        description: "Lincoln's autobiography — self-generated reflections"
      }
    ]
  end

  def read("lincoln://state") do
    with {:ok, agent} <- default_agent() do
      case Substrate.get_agent_state(agent.id) do
        {:ok, state} ->
          thoughts = Thoughts.list(agent.id)
          self_model = Lincoln.SelfModel.get(agent.id)

          text =
            [
              "=== Lincoln Cognitive State ===",
              "Agent: #{agent.name}",
              "Tick: #{state.tick_count}",
              "Focus: #{focus_text(state.current_focus)}",
              "Attention score: #{format_float(state.last_attention_score)}",
              "Tier: #{state.last_tier || "none"}",
              "Running thoughts: #{length(thoughts)}",
              if(self_model,
                do: "Self-model: #{Lincoln.SelfModel.to_summary_string(self_model)}",
                else: nil
              )
            ]
            |> Enum.reject(&is_nil/1)
            |> Enum.join("\n")

          resource_result("lincoln://state", "text/plain", text)

        {:error, :not_running} ->
          resource_result(
            "lincoln://state",
            "text/plain",
            "Substrate not running. Use the start_substrate tool."
          )
      end
    end
  end

  def read("lincoln://beliefs") do
    with {:ok, agent} <- default_agent() do
      beliefs = Beliefs.list_beliefs(agent, status: "active", limit: 50)

      data =
        Enum.map(beliefs, fn b ->
          %{
            id: b.id,
            statement: b.statement,
            confidence: b.confidence,
            source_type: b.source_type,
            entrenchment: b.entrenchment,
            revision_count: b.revision_count
          }
        end)

      json = Jason.encode!(%{count: length(data), beliefs: data}, pretty: true)
      resource_result("lincoln://beliefs", "application/json", json)
    end
  end

  def read("lincoln://thoughts") do
    with {:ok, agent} <- default_agent() do
      thoughts = Thoughts.list(agent.id)

      data =
        Enum.map(thoughts, fn t ->
          belief = Map.get(t, :belief) || %{}

          %{
            id: t.id,
            belief_statement: Map.get(belief, :statement),
            tier: t.tier,
            status: t.status,
            parent_id: t.parent_id,
            started_at: t.started_at
          }
        end)

      json = Jason.encode!(%{running: length(data), thoughts: data}, pretty: true)
      resource_result("lincoln://thoughts", "application/json", json)
    end
  end

  def read("lincoln://memories") do
    with {:ok, agent} <- default_agent() do
      memories =
        try do
          Memory.list_memories(agent, limit: 20)
        rescue
          _ -> []
        end

      data =
        Enum.map(memories, fn m ->
          %{
            id: m.id,
            content: m.content,
            memory_type: m.memory_type,
            importance: m.importance,
            created_at: m.inserted_at
          }
        end)

      json = Jason.encode!(%{count: length(data), memories: data}, pretty: true)
      resource_result("lincoln://memories", "application/json", json)
    end
  end

  def read("lincoln://narrative") do
    with {:ok, agent} <- default_agent() do
      reflections = Narratives.list_reflections(agent.id, limit: 10)

      text = format_reflections(reflections)

      resource_result("lincoln://narrative", "text/plain", text)
    end
  end

  def read(uri), do: {:error, "Unknown resource: #{uri}"}

  defp resource_result(uri, mime, text) do
    {:ok, %{contents: [%{uri: uri, mimeType: mime, text: text}]}}
  end

  defp format_reflections([]) do
    "No narrative reflections yet. Lincoln writes after every 200 substrate ticks."
  end

  defp format_reflections(reflections) do
    Enum.map_join(reflections, "\n\n", fn r ->
      date = Calendar.strftime(r.inserted_at, "%Y-%m-%d %H:%M")
      "--- #{date} (tick #{r.tick_number}) ---\n#{r.content}"
    end)
  end

  defp default_agent, do: Agents.get_or_create_default_agent()

  defp focus_text(nil), do: "None"

  defp focus_text(b) do
    stmt = Map.get(b, :statement, "?")
    conf = Map.get(b, :confidence, 0) |> Float.round(2)
    "\"#{stmt}\" (#{conf})"
  end

  defp format_float(nil), do: "N/A"
  defp format_float(f), do: f |> Float.round(3) |> to_string()
end
