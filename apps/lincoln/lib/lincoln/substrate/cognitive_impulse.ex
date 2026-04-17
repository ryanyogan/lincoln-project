defmodule Lincoln.Substrate.CognitiveImpulse do
  @moduledoc """
  Synthetic belief-like candidates that represent cognitive activities.

  Impulses compete directly with real beliefs in the Attention scoring pipeline.
  When an impulse wins, the Thought process routes to the appropriate
  cognitive function instead of doing standard belief reflection.

  Impulse types:
  - `:curiosity` — explore something new (high when belief set is stale)
  - `:reflection` — synthesize recent learning (high when many new beliefs)

  Each impulse has a cooldown to prevent runaway execution.
  """

  alias Lincoln.Beliefs

  @curiosity_cooldown_seconds 1800
  @reflection_cooldown_seconds 7200

  @doc """
  Returns a list of impulse candidates with computed scores.

  Each impulse is a map that looks like a belief to Attention:
  `%{id: "impulse:type", statement: ..., confidence: ..., ...}`
  """
  def candidates(agent, impulse_state, now) do
    [
      curiosity_impulse(agent, impulse_state, now),
      reflection_impulse(agent, impulse_state, now)
    ]
    |> Enum.reject(&is_nil/1)
  end

  @doc "Check if a belief ID represents an impulse."
  def impulse?(<<"impulse:" <> _rest>>), do: true
  def impulse?(_), do: false

  @doc "Extract the impulse type from an impulse ID."
  def impulse_type(<<"impulse:" <> type>>), do: String.to_existing_atom(type)

  @doc "Initial impulse state for the Attention struct."
  def initial_state do
    %{
      last_curiosity_at: nil,
      last_reflection_at: nil
    }
  end

  defp curiosity_impulse(agent, impulse_state, now) do
    if on_cooldown?(impulse_state.last_curiosity_at, now, @curiosity_cooldown_seconds) do
      nil
    else
      score = curiosity_score(agent)

      %{
        id: "impulse:curiosity",
        statement: "I should explore something new and generate questions",
        confidence: score,
        entrenchment: 1,
        source_type: "introspection",
        revision_count: 0,
        inserted_at: now,
        updated_at: now,
        last_challenged_at: nil,
        last_reinforced_at: nil,
        status: "active"
      }
    end
  end

  defp reflection_impulse(agent, impulse_state, now) do
    if on_cooldown?(impulse_state.last_reflection_at, now, @reflection_cooldown_seconds) do
      nil
    else
      score = reflection_score(agent)

      %{
        id: "impulse:reflection",
        statement: "I should reflect on what I have learned recently",
        confidence: score,
        entrenchment: 1,
        source_type: "introspection",
        revision_count: 0,
        inserted_at: now,
        updated_at: now,
        last_challenged_at: nil,
        last_reinforced_at: nil,
        status: "active"
      }
    end
  end

  defp on_cooldown?(nil, _now, _seconds), do: false

  defp on_cooldown?(last_at, now, seconds) do
    DateTime.diff(now, last_at, :second) < seconds
  end

  defp curiosity_score(agent) do
    # Score high when the belief set is going stale (few recent updates)
    beliefs = Beliefs.list_beliefs(agent, status: "active", limit: 50)

    if beliefs == [] do
      0.8
    else
      now = DateTime.utc_now()
      one_hour = 3600

      stale_count =
        Enum.count(beliefs, fn b ->
          b.updated_at != nil and DateTime.diff(now, b.updated_at, :second) > one_hour
        end)

      staleness_ratio = stale_count / length(beliefs)

      min(1.0, staleness_ratio * 0.6 + 0.1)
    end
  end

  defp reflection_score(agent) do
    # Score high when many beliefs have been recently created or revised
    beliefs = Beliefs.list_beliefs(agent, status: "active", limit: 50)

    if beliefs == [] do
      0.0
    else
      now = DateTime.utc_now()
      one_hour = 3600

      recent_count =
        Enum.count(beliefs, fn b ->
          (b.inserted_at != nil and DateTime.diff(now, b.inserted_at, :second) < one_hour) or
            b.revision_count > 0
        end)

      novelty_density = recent_count / length(beliefs)

      min(1.0, novelty_density * 0.7 + 0.1)
    end
  end
end
