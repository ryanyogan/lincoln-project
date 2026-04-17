defmodule Lincoln.Substrate.Skeptic do
  @moduledoc """
  Contradiction detection in the belief graph.

  Heuristic detection (no LLM):
  1. Picks a high-confidence active belief
  2. Finds semantically similar beliefs (embedding cosine similarity)
  3. Among similar beliefs, checks for contradiction signals:
     - Different source types with conflicting evidence
     - High confidence on both sides
     - One recently challenged while other is not
  4. Creates belief_relationship with type "contradicts"
  5. Broadcasts skeptic flag for Attention to notice

  Called periodically by the Substrate tick loop — not a GenServer.
  """

  require Logger

  alias Lincoln.{Beliefs, PubSubBroadcaster}

  @similarity_threshold 0.75

  @doc "Run one round of contradiction detection for the agent."
  def detect_contradictions(agent) do
    case pick_target_belief(agent) do
      nil -> :ok
      belief -> investigate_belief(belief, agent)
    end
  end

  defp pick_target_belief(agent) do
    beliefs = Beliefs.list_beliefs(agent, min_confidence: 0.7, limit: 10, status: "active")
    if beliefs == [], do: nil, else: Enum.random(beliefs)
  end

  defp investigate_belief(belief, agent) do
    case belief.embedding do
      nil ->
        :ok

      embedding ->
        similar =
          Beliefs.find_similar_beliefs(agent, embedding,
            limit: 5,
            threshold: @similarity_threshold
          )

        similar
        |> Enum.reject(fn b -> b.id == belief.id end)
        |> Enum.each(fn candidate ->
          check_and_flag_contradiction(belief, candidate, agent)
        end)
    end
  end

  defp check_and_flag_contradiction(belief_a, candidate, agent) do
    if contradiction_signals?(belief_a, candidate) do
      maybe_create_contradiction(belief_a, candidate, agent)
    end
  end

  defp contradiction_signals?(belief_a, belief_b) do
    both_confident = belief_a.confidence > 0.7 and belief_b.confidence > 0.7
    different_sources = belief_a.source_type != belief_b.source_type

    recently_challenged =
      not is_nil(belief_a.last_challenged_at) or not is_nil(belief_b.last_challenged_at)

    both_confident and (different_sources or recently_challenged)
  end

  defp maybe_create_contradiction(belief_a, belief_b, agent) do
    already_exists =
      Beliefs.relationship_exists?(agent, belief_a.id, belief_b.id, "contradicts") or
        Beliefs.relationship_exists?(agent, belief_b.id, belief_a.id, "contradicts")

    unless already_exists do
      attrs = %{
        agent_id: agent.id,
        source_belief_id: belief_a.id,
        target_belief_id: belief_b.id,
        relationship_type: "contradicts",
        confidence: min(belief_a.confidence, belief_b.confidence),
        detected_by: "skeptic",
        evidence:
          "Skeptic detected: both beliefs have confidence > 0.7, different sources or recently challenged"
      }

      case Beliefs.create_relationship(attrs) do
        {:ok, relationship} ->
          Logger.info(
            "[Skeptic #{agent.id}] Contradiction detected: #{belief_a.id} <-> #{belief_b.id}"
          )

          PubSubBroadcaster.broadcast_skeptic_flag(
            agent.id,
            {:contradiction_detected, relationship, belief_a, belief_b}
          )

        {:error, _} ->
          :ok
      end
    end
  end
end
