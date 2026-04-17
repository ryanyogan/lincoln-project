defmodule Lincoln.Substrate.ThoughtTest do
  use Lincoln.DataCase

  alias Lincoln.Substrate.Thought

  setup do
    {:ok, agent} = Lincoln.Agents.create_agent(%{name: "ThoughtTest #{System.unique_integer()}"})
    belief = %{id: Ecto.UUID.generate(), statement: "Test belief", confidence: 0.8}
    %{agent: agent, belief: belief}
  end

  describe "Level 0 (local) thought" do
    test "spawns, executes, and terminates normally", %{agent: agent, belief: belief} do
      pid =
        start_supervised!({Thought, %{agent_id: agent.id, belief: belief, attention_score: 0.1}})

      ref = Process.monitor(pid)

      assert_receive {:DOWN, ^ref, :process, ^pid, reason}, 2_000
      assert reason in [:normal, :noproc]
    end

    test "broadcasts thought_spawned and thought_completed events", %{
      agent: agent,
      belief: belief
    } do
      Phoenix.PubSub.subscribe(
        Lincoln.PubSub,
        Lincoln.PubSubBroadcaster.thought_topic(agent.id)
      )

      _pid =
        start_supervised!({Thought, %{agent_id: agent.id, belief: belief, attention_score: 0.1}})

      assert_receive {:thought_spawned, _id, "Test belief", :local, _parent}, 1_000
      assert_receive {:thought_completed, _id, summary}, 2_000
      assert summary =~ "Contemplating"
    end

    test "completed state is observable via PubSub events", %{agent: agent, belief: belief} do
      Phoenix.PubSub.subscribe(
        Lincoln.PubSub,
        Lincoln.PubSubBroadcaster.thought_topic(agent.id)
      )

      _pid =
        start_supervised!({Thought, %{agent_id: agent.id, belief: belief, attention_score: 0.1}})

      assert_receive {:thought_spawned, id, "Test belief", :local, _parent}, 1_000
      assert_receive {:thought_completed, ^id, result}, 2_000
      assert is_binary(id)
      assert result =~ "Contemplating"
    end
  end

  describe "thought initialization" do
    test "assigns :local tier for low attention score", %{agent: agent, belief: belief} do
      Phoenix.PubSub.subscribe(
        Lincoln.PubSub,
        Lincoln.PubSubBroadcaster.thought_topic(agent.id)
      )

      _pid =
        start_supervised!({Thought, %{agent_id: agent.id, belief: belief, attention_score: 0.1}})

      assert_receive {:thought_spawned, _id, _statement, :local, _parent}, 1_000
    end

    test "assigns :ollama tier for medium attention score", %{agent: agent, belief: belief} do
      Phoenix.PubSub.subscribe(
        Lincoln.PubSub,
        Lincoln.PubSubBroadcaster.thought_topic(agent.id)
      )

      _pid =
        start_supervised!({Thought, %{agent_id: agent.id, belief: belief, attention_score: 0.5}})

      assert_receive {:thought_spawned, _id, _statement, :ollama, _parent}, 1_000
    end

    test "assigns :claude tier for high attention score", %{agent: agent, belief: belief} do
      Phoenix.PubSub.subscribe(
        Lincoln.PubSub,
        Lincoln.PubSubBroadcaster.thought_topic(agent.id)
      )

      _pid =
        start_supervised!({Thought, %{agent_id: agent.id, belief: belief, attention_score: 0.9}})

      assert_receive {:thought_spawned, _id, _statement, :claude, _parent}, 1_000
    end

    test "generates unique thought ID", %{agent: agent, belief: belief} do
      Phoenix.PubSub.subscribe(
        Lincoln.PubSub,
        Lincoln.PubSubBroadcaster.thought_topic(agent.id)
      )

      _pid1 =
        start_supervised!(
          {Thought, %{agent_id: agent.id, belief: belief, attention_score: 0.1}},
          id: :thought_1
        )

      assert_receive {:thought_spawned, id1, _, _, _}, 1_000

      _pid2 =
        start_supervised!(
          {Thought, %{agent_id: agent.id, belief: belief, attention_score: 0.1}},
          id: :thought_2
        )

      assert_receive {:thought_spawned, id2, _, _, _}, 1_000
      assert id1 != id2
    end
  end

  describe "child_spec" do
    test "has restart: :temporary" do
      spec = Thought.child_spec(%{id: "test"})
      assert spec.restart == :temporary
      assert spec.type == :worker
    end
  end

  describe "local execution result" do
    test "result contains belief statement", %{agent: agent, belief: belief} do
      Phoenix.PubSub.subscribe(
        Lincoln.PubSub,
        Lincoln.PubSubBroadcaster.thought_topic(agent.id)
      )

      _pid =
        start_supervised!({Thought, %{agent_id: agent.id, belief: belief, attention_score: 0.1}})

      assert_receive {:thought_completed, _id, summary}, 2_000
      assert summary =~ "Test belief"
    end
  end
end
