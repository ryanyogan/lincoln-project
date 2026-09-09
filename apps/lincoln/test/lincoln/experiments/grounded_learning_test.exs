defmodule Lincoln.Experiments.GroundedLearningTest do
  @moduledoc "Deterministic longitudinal probes against real persistence; no LLM judge."
  use Lincoln.DataCase
  alias Lincoln.{Agents, Beliefs, FamilyJournal}
  alias Lincoln.Cognition.BeliefRevision
  alias Lincoln.Substrate.{InferenceTier, ReflectionFeedback, Resonator, Skeptic}

  setup do
    {:ok, agent} = Agents.create_agent(%{name: "Grounding #{System.unique_integer()}"})
    %{agent: agent}
  end

  test "100 self-confirmations do not manufacture confidence, unlike the old feedback rule", %{
    agent: agent
  } do
    {:ok, belief} =
      Beliefs.create_belief(agent, %{
        statement: "Saturday walks matter to our family",
        source_type: "inference",
        confidence: 0.6
      })

    {:ok, control} =
      Beliefs.create_belief(agent, %{
        statement: "Control account",
        source_type: "inference",
        confidence: 0.6
      })

    legacy =
      Enum.reduce(1..100, control, fn _, prior ->
        {:ok, updated} = Beliefs.strengthen_belief(prior, "Reinforced by reflection")
        updated
      end)

    for _ <- 1..100 do
      assert :unverified =
               ReflectionFeedback.apply(
                 agent,
                 belief,
                 "This remains a deeply meaningful family tradition."
               )
    end

    current = Beliefs.get_belief!(belief.id)
    assert legacy.confidence == 1.0
    assert current.confidence == 0.6
    assert current.entrenchment == belief.entrenchment
    assert Beliefs.list_revisions(current) == []
  end

  test "a later correction supersedes the old account and keeps its source", %{agent: agent} do
    {:ok, belief} =
      Beliefs.create_belief(agent, %{
        statement: "Our walks are on Saturday",
        source_type: "inference",
        confidence: 0.6
      })

    evidence = %{
      statement: "Our walks are now on Sunday",
      source_type: :testimony,
      strength: :strong,
      source_evidence: "Family correction, September 8"
    }

    decision = BeliefRevision.should_revise?(belief, evidence)
    assert {:revise, _} = decision
    assert {:ok, corrected} = BeliefRevision.execute_revision(belief, evidence, decision)
    assert corrected.statement == evidence.statement
    assert corrected.source_type == "testimony"
    assert corrected.source_evidence == evidence.source_evidence
    previous = Beliefs.get_belief!(belief.id)
    assert previous.status == "superseded"
    assert previous.contradicted_by_id == corrected.id
    assert [revision] = Beliefs.list_revisions(previous)
    assert revision.revision_type == "superseded"
    assert Enum.map(Beliefs.list_beliefs(agent, status: "active"), & &1.id) == [corrected.id]
  end

  test "repeated doubt queues investigation without eroding a belief", %{agent: agent} do
    {:ok, belief} =
      Beliefs.create_belief(agent, %{
        statement: "Our walks are on Sunday",
        source_type: "testimony",
        confidence: 0.8
      })

    for _ <- 1..10 do
      ReflectionFeedback.apply(agent, belief, "However this might be incorrect.")
    end

    assert Beliefs.get_belief!(belief.id).confidence == 0.8
    assert length(Lincoln.Questions.list_questions(agent)) == 1
  end

  test "semantic neighbors are not proof of support or contradiction", %{agent: agent} do
    vector = Pgvector.new([1.0 | List.duplicate(0.0, 383)])

    beliefs =
      for {statement, source} <- [
            {"I like morning walks", "testimony"},
            {"I dislike morning walks", "observation"},
            {"Morning walks are outdoors", "inference"}
          ] do
        {:ok, belief} =
          Beliefs.create_belief(agent, %{
            statement: statement,
            source_type: source,
            confidence: 0.85,
            embedding: vector
          })

        belief
      end

    Resonator.detect_cascades(agent)
    Skeptic.detect_contradictions(agent)

    for belief <- beliefs do
      relationships = Beliefs.find_relationships(agent, belief.id)
      refute Enum.any?(relationships, &(&1.relationship_type in ["supports", "contradicts"]))
      assert InferenceTier.select_tier(0.9, agent: agent, belief: belief) == :claude
    end
  end

  test "family words survive export and remain attributed in conversational context", %{
    agent: agent
  } do
    words = "When you need me, remember our Sunday walks.\nLove, Dad."

    {:ok, entry} =
      FamilyJournal.record(agent, %{"author" => "Dad", "kind" => "story", "content" => words})

    {:ok, _} =
      FamilyJournal.record(agent, %{
        "author" => "Dad",
        "kind" => "correction",
        "content" => "We moved our walks to Monday."
      })

    assert [%{content: ^words}] =
             Enum.filter(FamilyJournal.export(agent).entries, &(&1.id == entry.id))

    context = FamilyJournal.context(agent)
    assert context =~ "Dad"
    assert context =~ entry.id
    assert context =~ "Monday"
    assert FamilyJournal.list(agent, search: "Sunday") |> length() == 1
  end
end
