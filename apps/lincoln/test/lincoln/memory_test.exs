defmodule Lincoln.MemoryTest do
  use Lincoln.DataCase, async: true

  alias Lincoln.{Agents, Memory}
  alias Lincoln.Memory.Memory, as: MemorySchema

  describe "memories" do
    setup do
      {:ok, agent} = Agents.create_agent(%{name: "Test Agent #{System.unique_integer()}"})
      %{agent: agent}
    end

    @valid_attrs %{
      content: "I observed the user asking about weather",
      memory_type: "observation",
      importance: 7
    }

    test "create_memory/2 creates a memory for an agent", %{agent: agent} do
      assert {:ok, %MemorySchema{} = memory} = Memory.create_memory(agent, @valid_attrs)
      assert memory.content == "I observed the user asking about weather"
      assert memory.memory_type == "observation"
      assert memory.importance == 7
      assert memory.agent_id == agent.id
    end

    test "list_memories/1 returns memories for an agent", %{agent: agent} do
      {:ok, memory1} = Memory.create_memory(agent, @valid_attrs)
      {:ok, memory2} = Memory.create_memory(agent, %{@valid_attrs | content: "Another memory"})

      memories = Memory.list_memories(agent)
      assert length(memories) == 2
      # Should be ordered by recency (most recent first)
      memory_ids = Enum.map(memories, & &1.id)
      assert memory2.id in memory_ids
      assert memory1.id in memory_ids
    end

    test "list_memories_by_type/3 filters by memory type", %{agent: agent} do
      {:ok, obs} = Memory.create_memory(agent, @valid_attrs)

      {:ok, _ref} =
        Memory.create_memory(agent, %{
          @valid_attrs
          | content: "Reflection",
            memory_type: "reflection"
        })

      observations = Memory.list_memories_by_type(agent, "observation")
      assert length(observations) == 1
      assert hd(observations).id == obs.id
    end

    test "list_recent_memories/3 returns memories within time window", %{agent: agent} do
      {:ok, memory} = Memory.create_memory(agent, @valid_attrs)

      recent = Memory.list_recent_memories(agent, 24)
      assert length(recent) == 1
      assert hd(recent).id == memory.id
    end

    test "record_observation/3 creates an observation memory", %{agent: agent} do
      {:ok, memory} = Memory.record_observation(agent, "User clicked the button", importance: 6)

      assert memory.memory_type == "observation"
      assert memory.content == "User clicked the button"
      assert memory.importance == 6
    end

    test "record_reflection/3 creates a reflection memory", %{agent: agent} do
      {:ok, memory} =
        Memory.record_reflection(agent, "I notice I ask similar questions", importance: 8)

      assert memory.memory_type == "reflection"
      assert memory.content == "I notice I ask similar questions"
      assert memory.importance == 8
    end

    test "record_conversation/3 creates a conversation memory", %{agent: agent} do
      {:ok, memory} = Memory.record_conversation(agent, "User: Hello! Agent: Hi there!")

      assert memory.memory_type == "conversation"
      assert memory.content == "User: Hello! Agent: Hi there!"
    end

    test "touch_memory/1 updates access tracking", %{agent: agent} do
      {:ok, memory} = Memory.create_memory(agent, @valid_attrs)
      assert memory.access_count == 0
      assert memory.last_accessed_at == nil

      {:ok, touched} = Memory.touch_memory(memory)
      assert touched.access_count == 1
      assert touched.last_accessed_at != nil
    end

    test "get_memory!/1 returns the memory", %{agent: agent} do
      {:ok, memory} = Memory.create_memory(agent, @valid_attrs)
      fetched = Memory.get_memory!(memory.id)
      assert fetched.id == memory.id
    end
  end
end
