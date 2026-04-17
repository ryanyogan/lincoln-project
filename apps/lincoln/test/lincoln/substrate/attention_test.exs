defmodule Lincoln.Substrate.AttentionTest do
  use Lincoln.DataCase

  alias Lincoln.{Agents, Beliefs}
  alias Lincoln.Substrate.Attention

  setup do
    {:ok, agent} = Agents.create_agent(%{name: "Attention Test #{System.unique_integer()}"})
    %{agent: agent}
  end

  describe "next_thought/1" do
    test "returns an impulse when agent has no beliefs", %{agent: agent} do
      pid = start_supervised!({Attention, %{agent_id: agent.id}})
      # With no beliefs, cognitive impulses (curiosity/reflection) still compete
      {:ok, candidate, score, _detail} = Attention.next_thought(pid)
      assert candidate != nil
      assert candidate.id =~ "impulse:"
      assert is_float(score)
    end

    test "returns a belief with a computed score", %{agent: agent} do
      {:ok, _b1} =
        Beliefs.create_belief(agent, %{
          statement: "Scored belief",
          source_type: "observation",
          confidence: 0.9,
          entrenchment: 2
        })

      pid = start_supervised!({Attention, %{agent_id: agent.id}})
      {:ok, belief, score, _detail} = Attention.next_thought(pid)
      assert belief.statement == "Scored belief"
      assert is_float(score)
      assert score > 0.0
    end

    test "focused params rank high-confidence tensioned beliefs higher", %{agent: _agent} do
      focused_params = %{
        "novelty_weight" => 0.2,
        "focus_momentum" => 0.8,
        "interrupt_threshold" => 0.8,
        "boredom_decay" => 0.05,
        "depth_preference" => 0.8
      }

      {:ok, focused_agent} =
        Agents.create_agent(%{
          name: "Focused #{System.unique_integer()}",
          attention_params: focused_params
        })

      now = DateTime.utc_now() |> DateTime.truncate(:second)
      one_hour_ago = DateTime.add(now, -3600, :second)

      {:ok, _deep} =
        Beliefs.create_belief(focused_agent, %{
          statement: "Deep entrenched belief",
          source_type: "training",
          confidence: 0.95,
          entrenchment: 9
        })

      {:ok, _shallow} =
        Beliefs.create_belief(focused_agent, %{
          statement: "Shallow new belief",
          source_type: "observation",
          confidence: 0.3,
          entrenchment: 1
        })

      {:ok, _tensioned} =
        Beliefs.create_belief(focused_agent, %{
          statement: "Tensioned belief",
          source_type: "inference",
          confidence: 0.9,
          entrenchment: 2,
          last_challenged_at: one_hour_ago
        })

      pid = start_supervised!({Attention, %{agent_id: focused_agent.id}})
      {:ok, belief, _score, _detail} = Attention.next_thought(pid)

      assert belief.statement in ["Deep entrenched belief", "Tensioned belief"]
    end

    test "butterfly params rank novel beliefs higher", %{agent: _agent} do
      butterfly_params = %{
        "novelty_weight" => 0.8,
        "focus_momentum" => 0.2,
        "interrupt_threshold" => 0.3,
        "boredom_decay" => 0.3,
        "depth_preference" => 0.2
      }

      {:ok, butterfly_agent} =
        Agents.create_agent(%{
          name: "Butterfly #{System.unique_integer()}",
          attention_params: butterfly_params
        })

      {:ok, _old_deep} =
        Beliefs.create_belief(butterfly_agent, %{
          statement: "Old deep belief",
          source_type: "training",
          confidence: 0.95,
          entrenchment: 9
        })

      {:ok, _novel} =
        Beliefs.create_belief(butterfly_agent, %{
          statement: "Fresh observation",
          source_type: "observation",
          confidence: 0.4,
          entrenchment: 1
        })

      pid = start_supervised!({Attention, %{agent_id: butterfly_agent.id}})
      {:ok, _belief, _score, detail} = Attention.next_thought(pid)

      # Among real beliefs (not impulses), novel observation should rank higher than deep training
      real_beliefs =
        detail.top_candidates
        |> Enum.reject(&String.starts_with?(&1.belief_id, "impulse:"))

      [top_belief | _] = real_beliefs
      assert top_belief.statement =~ "Fresh observation"
    end

    test "different params produce different orderings from same beliefs" do
      focused_params = %{
        "novelty_weight" => 0.2,
        "focus_momentum" => 0.8,
        "interrupt_threshold" => 0.8,
        "boredom_decay" => 0.05,
        "depth_preference" => 0.8
      }

      butterfly_params = %{
        "novelty_weight" => 0.8,
        "focus_momentum" => 0.2,
        "interrupt_threshold" => 0.3,
        "boredom_decay" => 0.3,
        "depth_preference" => 0.2
      }

      {:ok, agent_a} =
        Agents.create_agent(%{
          name: "AgentA #{System.unique_integer()}",
          attention_params: focused_params
        })

      {:ok, agent_b} =
        Agents.create_agent(%{
          name: "AgentB #{System.unique_integer()}",
          attention_params: butterfly_params
        })

      for agent <- [agent_a, agent_b] do
        {:ok, _} =
          Beliefs.create_belief(agent, %{
            statement: "Core training belief about systems",
            source_type: "training",
            confidence: 0.8,
            entrenchment: 5
          })

        {:ok, _} =
          Beliefs.create_belief(agent, %{
            statement: "Fresh observation about behavior",
            source_type: "observation",
            confidence: 0.4,
            entrenchment: 1
          })
      end

      pid_a = start_supervised!({Attention, %{agent_id: agent_a.id}}, id: :attn_a)
      pid_b = start_supervised!({Attention, %{agent_id: agent_b.id}}, id: :attn_b)

      {:ok, _belief_a, score_a, detail_a} = Attention.next_thought(pid_a)
      {:ok, _belief_b, score_b, detail_b} = Attention.next_thought(pid_b)

      # Different params should produce different scores for the same beliefs
      assert score_a != score_b

      # The scoring details should show different candidate orderings
      real_a = Enum.reject(detail_a.top_candidates, &String.starts_with?(&1.belief_id, "impulse:"))
      real_b = Enum.reject(detail_b.top_candidates, &String.starts_with?(&1.belief_id, "impulse:"))

      scores_a = Enum.map(real_a, & &1.components.final_score)
      scores_b = Enum.map(real_b, & &1.components.final_score)
      assert scores_a != scores_b
    end

    test "successive calls rotate through beliefs via staleness" do
      {:ok, rotator} =
        Agents.create_agent(%{
          name: "Rotator #{System.unique_integer()}",
          attention_params: %{
            "novelty_weight" => 0.1,
            "focus_momentum" => 0.0,
            "interrupt_threshold" => 0.7,
            "boredom_decay" => 0.5,
            "depth_preference" => 0.1
          }
        })

      {:ok, _b1} =
        Beliefs.create_belief(rotator, %{
          statement: "Alpha",
          source_type: "observation",
          confidence: 0.5,
          entrenchment: 5
        })

      {:ok, _b2} =
        Beliefs.create_belief(rotator, %{
          statement: "Beta",
          source_type: "observation",
          confidence: 0.5,
          entrenchment: 5
        })

      pid = start_supervised!({Attention, %{agent_id: rotator.id}})
      {:ok, b1, _, _} = Attention.next_thought(pid)
      {:ok, b2, _, _} = Attention.next_thought(pid)

      assert b1.id != b2.id
    end
  end

  describe "score_breakdown/2" do
    test "returns map with expected keys", %{agent: agent} do
      {:ok, belief} =
        Beliefs.create_belief(agent, %{
          statement: "Breakdownable",
          source_type: "observation",
          confidence: 0.7,
          entrenchment: 5
        })

      pid = start_supervised!({Attention, %{agent_id: agent.id}})
      breakdown = Attention.score_breakdown(pid, belief.id)

      assert is_map(breakdown)
      assert Map.has_key?(breakdown, :novelty)
      assert Map.has_key?(breakdown, :tension)
      assert Map.has_key?(breakdown, :staleness)
      assert Map.has_key?(breakdown, :depth)
      assert Map.has_key?(breakdown, :total)

      assert is_float(breakdown.novelty)
      assert is_float(breakdown.tension)
      assert is_float(breakdown.staleness)
      assert is_float(breakdown.depth)
      assert is_float(breakdown.total)
    end

    test "novelty is higher for observations than training", %{agent: agent} do
      {:ok, obs} =
        Beliefs.create_belief(agent, %{
          statement: "Observed",
          source_type: "observation",
          confidence: 0.5,
          entrenchment: 5
        })

      {:ok, train} =
        Beliefs.create_belief(agent, %{
          statement: "Trained",
          source_type: "training",
          confidence: 0.5,
          entrenchment: 5
        })

      pid = start_supervised!({Attention, %{agent_id: agent.id}})
      obs_breakdown = Attention.score_breakdown(pid, obs.id)
      train_breakdown = Attention.score_breakdown(pid, train.id)

      assert obs_breakdown.novelty > train_breakdown.novelty
    end
  end

  test "registers in AgentRegistry", %{agent: agent} do
    _pid = start_supervised!({Attention, %{agent_id: agent.id}})
    [{pid, _}] = Registry.lookup(Lincoln.AgentRegistry, {agent.id, :attention})
    assert is_pid(pid)
  end
end
