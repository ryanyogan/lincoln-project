defmodule Lincoln.PubSubBroadcaster do
  @moduledoc """
  Handles PubSub broadcasting for real-time updates.

  Topics:
  - `agent:{agent_id}` - general agent updates
  - `agent:{agent_id}:beliefs` - belief updates
  - `agent:{agent_id}:questions` - question updates
  - `agent:{agent_id}:memories` - memory updates
  """

  @pubsub Lincoln.PubSub

  # ============================================================================
  # Beliefs
  # ============================================================================

  def broadcast_belief_created(agent_id, belief) do
    broadcast(agent_topic(agent_id, :beliefs), {:belief_created, belief})
    broadcast(agent_topic(agent_id), {:belief_created, belief})
  end

  def broadcast_belief_updated(agent_id, belief) do
    broadcast(agent_topic(agent_id, :beliefs), {:belief_updated, belief})
    broadcast(agent_topic(agent_id), {:belief_updated, belief})
  end

  def broadcast_belief_revised(agent_id, belief, revision) do
    broadcast(agent_topic(agent_id, :beliefs), {:belief_revised, belief, revision})
    broadcast(agent_topic(agent_id), {:belief_revised, belief, revision})
  end

  # ============================================================================
  # Questions
  # ============================================================================

  def broadcast_question_created(agent_id, question) do
    broadcast(agent_topic(agent_id, :questions), {:question_created, question})
    broadcast(agent_topic(agent_id), {:question_created, question})
  end

  def broadcast_question_updated(agent_id, question) do
    broadcast(agent_topic(agent_id, :questions), {:question_updated, question})
    broadcast(agent_topic(agent_id), {:question_updated, question})
  end

  def broadcast_question_resolved(agent_id, question, finding) do
    broadcast(agent_topic(agent_id, :questions), {:question_resolved, question, finding})
    broadcast(agent_topic(agent_id), {:question_resolved, question, finding})
  end

  def broadcast_finding_created(agent_id, finding) do
    broadcast(agent_topic(agent_id, :questions), {:finding_created, finding})
    broadcast(agent_topic(agent_id), {:finding_created, finding})
  end

  # ============================================================================
  # Memories
  # ============================================================================

  def broadcast_memory_created(agent_id, memory) do
    broadcast(agent_topic(agent_id, :memories), {:memory_created, memory})
    broadcast(agent_topic(agent_id), {:memory_created, memory})
  end

  def broadcast_memory_updated(agent_id, memory) do
    broadcast(agent_topic(agent_id, :memories), {:memory_updated, memory})
    broadcast(agent_topic(agent_id), {:memory_updated, memory})
  end

  # ============================================================================
  # Actions
  # ============================================================================

  def broadcast_action_logged(agent_id, action) do
    broadcast(agent_topic(agent_id), {:action_logged, action})
  end

  def broadcast_action_completed(agent_id, action) do
    broadcast(agent_topic(agent_id), {:action_completed, action})
  end

  # ============================================================================
  # Autonomy
  # ============================================================================

  def broadcast_autonomy_event(agent_id, event) do
    broadcast(agent_topic(agent_id, :autonomy), event)
    broadcast(agent_topic(agent_id), event)
  end

  # ============================================================================
  # Helpers
  # ============================================================================

  defp agent_topic(agent_id) do
    "agent:#{agent_id}"
  end

  defp agent_topic(agent_id, :beliefs), do: "agent:#{agent_id}:beliefs"
  defp agent_topic(agent_id, :questions), do: "agent:#{agent_id}:questions"
  defp agent_topic(agent_id, :memories), do: "agent:#{agent_id}:memories"
  defp agent_topic(agent_id, :autonomy), do: "agent:#{agent_id}:autonomy"

  @doc """
  Generic broadcast to any topic.
  """
  def broadcast(topic, message) do
    Phoenix.PubSub.broadcast(@pubsub, topic, message)
  end
end
