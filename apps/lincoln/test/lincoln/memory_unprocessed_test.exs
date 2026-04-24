defmodule Lincoln.MemoryUnprocessedTest do
  use Lincoln.DataCase, async: true

  alias Lincoln.{Agents, Memory}

  setup do
    {:ok, agent} = Agents.create_agent(%{name: "Mem Unproc #{System.unique_integer()}"})
    %{agent: agent}
  end

  describe "count_unprocessed_observations/2" do
    test "counts only observation memories without processed_at", %{agent: agent} do
      {:ok, _unprocessed} =
        Memory.create_memory(agent, %{
          content: "fresh",
          memory_type: "observation",
          source_context: %{"source" => "test"}
        })

      {:ok, _processed} =
        Memory.create_memory(agent, %{
          content: "already processed",
          memory_type: "observation",
          source_context: %{"source" => "test", "processed_at" => "2026-01-01T00:00:00Z"}
        })

      {:ok, _reflection} =
        Memory.create_memory(agent, %{
          content: "a reflection, ignored",
          memory_type: "reflection"
        })

      assert Memory.count_unprocessed_observations(agent) == 1
    end
  end

  describe "list_unprocessed_observations/2" do
    test "orders by importance desc then recency desc", %{agent: agent} do
      {:ok, _low} = obs(agent, "low", 3)
      {:ok, high} = obs(agent, "high", 9)
      {:ok, _mid} = obs(agent, "mid", 6)

      [first | _] = Memory.list_unprocessed_observations(agent, limit: 3)
      assert first.id == high.id
    end

    test "excludes already-processed observations", %{agent: agent} do
      {:ok, processed} = obs(agent, "already done", 8)
      {:ok, _} = Memory.mark_processed(processed)

      {:ok, fresh} = obs(agent, "still fresh", 5)

      assert [%{id: id}] = Memory.list_unprocessed_observations(agent, limit: 5)
      assert id == fresh.id
    end
  end

  describe "mark_processed/2" do
    test "stamps processed_at and adds belief id when given", %{agent: agent} do
      {:ok, memory} = obs(agent, "to process", 5)
      belief_id = Ecto.UUID.generate()

      assert {:ok, updated} = Memory.mark_processed(memory, belief_id: belief_id)
      assert updated.source_context["processed_at"]
      assert belief_id in updated.related_belief_ids
    end

    test "preserves prior related_belief_ids", %{agent: agent} do
      existing = Ecto.UUID.generate()

      {:ok, memory} =
        Memory.create_memory(agent, %{
          content: "had a belief already",
          memory_type: "observation",
          source_context: %{},
          related_belief_ids: [existing]
        })

      new_id = Ecto.UUID.generate()
      assert {:ok, updated} = Memory.mark_processed(memory, belief_id: new_id)
      assert existing in updated.related_belief_ids
      assert new_id in updated.related_belief_ids
    end
  end

  defp obs(agent, content, importance) do
    Memory.create_memory(agent, %{
      content: content,
      memory_type: "observation",
      importance: importance,
      source_context: %{"source" => "test"}
    })
  end
end
