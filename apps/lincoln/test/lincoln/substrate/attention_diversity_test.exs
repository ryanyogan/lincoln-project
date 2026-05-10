defmodule Lincoln.Substrate.AttentionDiversityTest do
  use Lincoln.DataCase

  alias Lincoln.{Agents, Beliefs}
  alias Lincoln.Substrate.Attention

  setup do
    {:ok, agent} = Agents.create_agent(%{name: "Attention Diversity #{System.unique_integer()}"})
    %{agent: agent}
  end

  describe "depth_score with entrenchment_dampening" do
    test "dampening=0.5 reduces depth score compared to no dampening", %{agent: agent} do
      {:ok, belief} =
        Beliefs.create_belief(agent, %{
          statement: "High entrenchment belief",
          source_type: "training",
          confidence: 0.5,
          entrenchment: 8
        })

      pid = start_supervised!({Attention, %{agent_id: agent.id}})

      # Get baseline score with default dampening (0.0)
      baseline = Attention.score_breakdown(pid, belief.id)

      # Update to dampening=0.5
      Agents.update_agent(agent, %{
        attention_params: %{
          "novelty_weight" => 0.3,
          "focus_momentum" => 0.5,
          "interrupt_threshold" => 0.7,
          "boredom_decay" => 0.1,
          "depth_preference" => 0.5,
          "entrenchment_dampening" => 0.5,
          "suppressed_belief_ids" => []
        }
      })

      GenServer.cast(pid, {:reload_params})
      Process.sleep(50)

      dampened = Attention.score_breakdown(pid, belief.id)

      # Depth score should be lower with dampening since entrenchment
      # contribution to raw score is halved
      assert dampened.depth < baseline.depth
    end

    test "higher dampening produces lower depth score", %{agent: _agent} do
      {:ok, dampened_agent} =
        Agents.create_agent(%{
          name: "Full Damp #{System.unique_integer()}",
          attention_params: %{
            "novelty_weight" => 0.3,
            "focus_momentum" => 0.5,
            "interrupt_threshold" => 0.7,
            "boredom_decay" => 0.1,
            "depth_preference" => 0.5,
            "entrenchment_dampening" => 1.0,
            "suppressed_belief_ids" => []
          }
        })

      # Use low entrenchment to avoid the settled_penalty for e>=7
      {:ok, belief} =
        Beliefs.create_belief(dampened_agent, %{
          statement: "Moderate entrenchment belief",
          source_type: "observation",
          confidence: 0.5,
          entrenchment: 4
        })

      pid = start_supervised!({Attention, %{agent_id: dampened_agent.id}})

      # With dampening=1.0, entrenchment contributes 0 to raw depth score
      # raw = confidence * 0.5 + (entrenchment * 0.0 / 20.0) * 0.5 = 0.25
      breakdown = Attention.score_breakdown(pid, belief.id)

      # Depth should be very low since entrenchment is fully dampened
      # and the settled_penalty further reduces it
      assert breakdown.depth < 0.3
    end
  end

  describe "suppressed_belief_ids" do
    test "suppressed belief gets lower score than unsuppressed", %{agent: _agent} do
      {:ok, suppressed_agent} =
        Agents.create_agent(%{
          name: "Suppressed #{System.unique_integer()}",
          attention_params: %{
            "novelty_weight" => 0.3,
            "focus_momentum" => 0.5,
            "interrupt_threshold" => 0.7,
            "boredom_decay" => 0.1,
            "depth_preference" => 0.5,
            "entrenchment_dampening" => 0.0,
            "suppressed_belief_ids" => []
          }
        })

      {:ok, target} =
        Beliefs.create_belief(suppressed_agent, %{
          statement: "Target belief to suppress",
          source_type: "observation",
          confidence: 0.9,
          entrenchment: 3
        })

      {:ok, _other} =
        Beliefs.create_belief(suppressed_agent, %{
          statement: "Normal unsuppressed belief",
          source_type: "observation",
          confidence: 0.9,
          entrenchment: 3
        })

      # First get baseline scores without suppression
      pid = start_supervised!({Attention, %{agent_id: suppressed_agent.id}})
      baseline_target = Attention.score_breakdown(pid, target.id)

      # Now suppress the target belief
      Agents.update_agent(suppressed_agent, %{
        attention_params: %{
          "novelty_weight" => 0.3,
          "focus_momentum" => 0.5,
          "interrupt_threshold" => 0.7,
          "boredom_decay" => 0.1,
          "depth_preference" => 0.5,
          "entrenchment_dampening" => 0.0,
          "suppressed_belief_ids" => [target.id]
        }
      })

      GenServer.cast(pid, {:reload_params})
      Process.sleep(50)

      # Use next_thought which applies the suppression penalty
      {:ok, _winner, _score, detail} = Attention.next_thought(pid)

      # Find the target's final score in the candidates list
      suppressed_candidate =
        Enum.find(detail.top_candidates, &(&1.belief_id == target.id))

      if suppressed_candidate do
        # The suppressed belief's final_score should be much lower
        # than its baseline total (which didn't include the -0.8 penalty)
        assert suppressed_candidate.components.final_score < baseline_target.total
        assert suppressed_candidate.components.suppression_penalty == 0.8
      end

      # The suppressed belief should not be the winner among real beliefs
      real_winner =
        detail.top_candidates
        |> Enum.reject(&String.starts_with?(&1.belief_id, "impulse:"))
        |> List.first()

      if real_winner do
        assert real_winner.belief_id != target.id
      end
    end
  end
end
