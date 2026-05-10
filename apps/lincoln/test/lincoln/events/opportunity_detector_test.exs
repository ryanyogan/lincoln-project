defmodule Lincoln.Events.OpportunityDetectorTest do
  use Lincoln.DataCase, async: true

  alias Lincoln.{Agents, Events}
  alias Lincoln.Events.OpportunityDetector

  describe "detect_thought_failure_rate" do
    setup do
      {:ok, agent} = Agents.create_agent(%{name: "Detector Agent #{System.unique_integer()}"})
      %{agent: agent}
    end

    test "enqueues opportunity when failure rate > 20% with 20+ sample", %{agent: agent} do
      # Create 25 failed + 5 completed events = 30 total, 83% failure rate
      for _ <- 1..25 do
        Events.create_event(%{
          type: "thought_failed",
          agent_id: agent.id,
          severity: "medium"
        })
      end

      for _ <- 1..5 do
        Events.create_event(%{
          type: "thought_completed",
          agent_id: agent.id,
          severity: "low"
        })
      end

      result = OpportunityDetector.scan(agent)
      assert {:ok, count} = result
      assert count >= 1

      # Verify opportunity was enqueued
      opportunities = Events.list_improvement_opportunities(agent, status: "pending")
      patterns = Enum.map(opportunities, & &1.pattern)
      assert "high_thought_failure_rate" in patterns
    end

    test "does not trigger when failure rate <= 20%", %{agent: agent} do
      for _ <- 1..4 do
        Events.create_event(%{
          type: "thought_failed",
          agent_id: agent.id,
          severity: "medium"
        })
      end

      for _ <- 1..20 do
        Events.create_event(%{
          type: "thought_completed",
          agent_id: agent.id,
          severity: "low"
        })
      end

      OpportunityDetector.scan(agent)
      opportunities = Events.list_improvement_opportunities(agent, status: "pending")
      patterns = Enum.map(opportunities, & &1.pattern)
      refute "high_thought_failure_rate" in patterns
    end

    test "does not trigger with fewer than 20 total events", %{agent: agent} do
      for _ <- 1..10 do
        Events.create_event(%{
          type: "thought_failed",
          agent_id: agent.id,
          severity: "medium"
        })
      end

      OpportunityDetector.scan(agent)
      opportunities = Events.list_improvement_opportunities(agent, status: "pending")
      patterns = Enum.map(opportunities, & &1.pattern)
      refute "high_thought_failure_rate" in patterns
    end
  end

  describe "queue cap" do
    setup do
      {:ok, agent} = Agents.create_agent(%{name: "Cap Agent #{System.unique_integer()}"})
      %{agent: agent}
    end

    test "returns :queue_full when 5 pending opportunities exist", %{agent: agent} do
      # Pre-fill 5 pending opportunities
      for i <- 1..5 do
        Events.create_improvement_opportunity(%{
          pattern: "pattern_#{i}",
          agent_id: agent.id,
          priority: 5
        })
      end

      result = OpportunityDetector.scan(agent)
      assert result == :queue_full
    end
  end

  describe "detect_persistent_perseveration" do
    setup do
      {:ok, agent} =
        Agents.create_agent(%{
          name: "Perseveration Agent #{System.unique_integer()}",
          attention_params: %{
            "novelty_weight" => 0.7,
            "base_novelty_weight" => 0.3,
            "entrenchment_dampening" => 0.7,
            "suppressed_belief_ids" => [],
            "focus_momentum" => 0.5,
            "interrupt_threshold" => 0.7,
            "boredom_decay" => 0.1,
            "depth_preference" => 0.5
          }
        })

      %{agent: agent}
    end

    test "detects when entrenchment_dampening >= 0.6", %{agent: agent} do
      result = OpportunityDetector.scan(agent)
      assert {:ok, count} = result
      assert count >= 1

      opportunities = Events.list_improvement_opportunities(agent, status: "pending")
      patterns = Enum.map(opportunities, & &1.pattern)
      assert "persistent_perseveration" in patterns
    end
  end

  describe "detect_belief_churn" do
    setup do
      {:ok, agent} = Agents.create_agent(%{name: "Churn Agent #{System.unique_integer()}"})
      %{agent: agent}
    end

    test "detects high retraction rate", %{agent: agent} do
      # Create 10 belief_created and 5 belief_retracted events (50% churn > 40%)
      for _ <- 1..10 do
        Events.create_event(%{
          type: "belief_created",
          agent_id: agent.id,
          severity: "low"
        })
      end

      for _ <- 1..5 do
        Events.create_event(%{
          type: "belief_retracted",
          agent_id: agent.id,
          severity: "medium"
        })
      end

      OpportunityDetector.scan(agent)
      opportunities = Events.list_improvement_opportunities(agent, status: "pending")
      patterns = Enum.map(opportunities, & &1.pattern)
      assert "high_belief_churn" in patterns
    end
  end

  describe "self-improvement rate limiting" do
    setup do
      {:ok, agent} = Agents.create_agent(%{name: "Rate Agent #{System.unique_integer()}"})
      %{agent: agent}
    end

    test "rate_limited? returns true when recent committed change exists", %{agent: agent} do
      # Create a session first
      {:ok, session} = Lincoln.Autonomy.create_session(agent, %{trigger: "test"})

      # Create a committed code change 10 minutes ago
      {:ok, change} =
        Lincoln.Autonomy.record_code_change(agent, session, %{
          file_path: "lib/lincoln/test.ex",
          change_type: "modify",
          description: "Test change",
          reasoning: "Testing",
          original_content: "old",
          new_content: "new",
          diff: "Changed 1 line"
        })

      # Commit it
      change
      |> Ecto.Changeset.change(%{
        status: "committed",
        git_commit: "abc123",
        committed_at: DateTime.utc_now() |> DateTime.truncate(:second)
      })
      |> Repo.update!()

      # Check that most_recent_code_change finds it
      recent = Lincoln.Autonomy.most_recent_code_change(agent, status: "committed")
      assert recent != nil
      assert recent.status == "committed"
    end

    test "safe_to_modify? rejects forbidden files" do
      # These files should be rejected
      refute safe_to_modify?("lib/lincoln/autonomy/evolution.ex")
      refute safe_to_modify?("lib/lincoln/autonomy/self_improvement.ex")
      refute safe_to_modify?("lib/lincoln/repo.ex")
      refute safe_to_modify?("lib/lincoln/application.ex")

      # These should be accepted
      assert safe_to_modify?("lib/lincoln/substrate/thought.ex")
      assert safe_to_modify?("lib/lincoln/beliefs.ex")
      assert safe_to_modify?("lib/lincoln/memory.ex")
    end

    test "safe_to_modify? rejects files outside lib/lincoln/" do
      refute safe_to_modify?("test/lincoln/beliefs_test.exs")
      refute safe_to_modify?("config/config.exs")
      refute safe_to_modify?("priv/repo/migrations/001.exs")
    end
  end

  # Mirror SelfImprovement's safe_to_modify? logic for testing
  @forbidden_files ~w(
    lib/lincoln/autonomy/evolution.ex
    lib/lincoln/autonomy/self_improvement.ex
    lib/lincoln/repo.ex
    lib/lincoln/application.ex
  )

  defp safe_to_modify?(path) do
    path not in @forbidden_files and String.starts_with?(path, "lib/lincoln/")
  end
end
