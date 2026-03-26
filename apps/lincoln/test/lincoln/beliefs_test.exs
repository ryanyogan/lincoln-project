defmodule Lincoln.BeliefsTest do
  use Lincoln.DataCase, async: true

  alias Lincoln.{Agents, Beliefs}
  alias Lincoln.Beliefs.Belief

  describe "beliefs" do
    setup do
      {:ok, agent} = Agents.create_agent(%{name: "Test Agent #{System.unique_integer()}"})
      %{agent: agent}
    end

    @valid_attrs %{
      statement: "The sky is blue",
      source_type: "observation",
      confidence: 0.8,
      entrenchment: 2
    }

    test "create_belief/2 creates a belief for an agent", %{agent: agent} do
      assert {:ok, %Belief{} = belief} = Beliefs.create_belief(agent, @valid_attrs)
      assert belief.statement == "The sky is blue"
      assert belief.source_type == "observation"
      assert belief.confidence == 0.8
      assert belief.entrenchment == 2
      assert belief.status == "active"
      assert belief.agent_id == agent.id
    end

    test "list_beliefs/1 returns beliefs for an agent", %{agent: agent} do
      {:ok, _belief1} = Beliefs.create_belief(agent, @valid_attrs)

      {:ok, belief2} =
        Beliefs.create_belief(agent, %{@valid_attrs | statement: "Water is wet", confidence: 0.9})

      beliefs = Beliefs.list_beliefs(agent)
      assert length(beliefs) == 2
      # Ordered by confidence desc
      assert hd(beliefs).id == belief2.id
    end

    test "list_beliefs_by_source/2 filters by source type", %{agent: agent} do
      {:ok, obs} = Beliefs.create_belief(agent, @valid_attrs)

      {:ok, _inf} =
        Beliefs.create_belief(agent, %{
          @valid_attrs
          | statement: "Derived fact",
            source_type: "inference"
        })

      observations = Beliefs.list_beliefs_by_source(agent, "observation")
      assert length(observations) == 1
      assert hd(observations).id == obs.id
    end

    test "list_core_beliefs/2 returns most entrenched beliefs", %{agent: agent} do
      {:ok, _low} = Beliefs.create_belief(agent, %{@valid_attrs | entrenchment: 1})

      {:ok, high} =
        Beliefs.create_belief(agent, %{@valid_attrs | statement: "Core belief", entrenchment: 8})

      {:ok, _mid} =
        Beliefs.create_belief(agent, %{@valid_attrs | statement: "Mid belief", entrenchment: 4})

      core = Beliefs.list_core_beliefs(agent, 2)
      assert length(core) == 2
      assert hd(core).id == high.id
    end

    test "strengthen_belief/3 increases confidence and records revision", %{agent: agent} do
      {:ok, belief} = Beliefs.create_belief(agent, %{@valid_attrs | confidence: 0.5})

      {:ok, strengthened} =
        Beliefs.strengthen_belief(belief, "New supporting evidence", boost: 0.2)

      assert strengthened.confidence == 0.7
      assert strengthened.revision_count == 1
      assert strengthened.last_reinforced_at != nil

      revisions = Beliefs.list_revisions(strengthened)
      assert length(revisions) == 1
      assert hd(revisions).revision_type == "strengthened"
    end

    test "weaken_belief/3 decreases confidence and records revision", %{agent: agent} do
      {:ok, belief} = Beliefs.create_belief(agent, %{@valid_attrs | confidence: 0.8})

      {:ok, weakened} = Beliefs.weaken_belief(belief, "Contradicting evidence", penalty: 0.2)

      assert_in_delta weakened.confidence, 0.6, 0.001
      assert weakened.revision_count == 1
      assert weakened.last_challenged_at != nil

      revisions = Beliefs.list_revisions(weakened)
      assert length(revisions) == 1
      assert hd(revisions).revision_type == "weakened"
    end

    test "retract_belief/3 marks belief as retracted", %{agent: agent} do
      {:ok, belief} = Beliefs.create_belief(agent, @valid_attrs)

      {:ok, retracted} = Beliefs.retract_belief(belief, "Proven false")

      assert retracted.status == "retracted"

      revisions = Beliefs.list_revisions(retracted)
      assert hd(revisions).revision_type == "retracted"
    end

    test "supersede_belief/3 creates new belief and marks old as superseded", %{agent: agent} do
      {:ok, old_belief} = Beliefs.create_belief(agent, @valid_attrs)

      new_attrs = %{
        statement: "The sky appears blue due to Rayleigh scattering",
        source_type: "inference",
        confidence: 0.9
      }

      {:ok, new_belief} =
        Beliefs.supersede_belief(old_belief, new_attrs, "More accurate explanation")

      assert new_belief.statement == new_attrs.statement
      assert new_belief.agent_id == agent.id

      old_updated = Beliefs.get_belief!(old_belief.id)
      assert old_updated.status == "superseded"
      assert old_updated.contradicted_by_id == new_belief.id
    end
  end

  describe "belief helpers" do
    test "experiential?/1 returns true for observation and inference" do
      assert Belief.experiential?(%Belief{source_type: "observation"})
      assert Belief.experiential?(%Belief{source_type: "inference"})
      refute Belief.experiential?(%Belief{source_type: "training"})
      refute Belief.experiential?(%Belief{source_type: "testimony"})
    end

    test "external?/1 returns true for training and testimony" do
      assert Belief.external?(%Belief{source_type: "training"})
      assert Belief.external?(%Belief{source_type: "testimony"})
      refute Belief.external?(%Belief{source_type: "observation"})
      refute Belief.external?(%Belief{source_type: "inference"})
    end
  end
end
