defmodule Lincoln.Substrate.CognitiveImpulse do
  @moduledoc """
  Synthetic belief-like candidates that represent cognitive activities.

  Impulses compete directly with real beliefs in the Attention scoring pipeline.
  When an impulse wins, the Thought process routes to the appropriate
  cognitive function instead of doing standard belief reflection.

  Impulse types:
  - `:curiosity` — explore something new (high when belief set is stale)
  - `:reflection` — synthesize recent learning (high when many new beliefs)
  - `:learning` — research a queued topic (high when topics are pending)

  Each impulse has a cooldown to prevent runaway execution.
  """

  alias Lincoln.{Autonomy, Questions}
  alias Lincoln.Events.ImprovementQueue

  @curiosity_cooldown_seconds 1800
  @reflection_cooldown_seconds 7200
  @learning_cooldown_seconds 300
  @investigation_cooldown_seconds 120
  @self_improve_cooldown_seconds 300

  @doc """
  Returns a list of impulse candidates with computed scores.

  Each impulse is a map that looks like a belief to Attention:
  `%{id: "impulse:type", statement: ..., confidence: ..., ...}`
  """
  def candidates(agent, impulse_state, now, beliefs \\ nil) do
    # Accept pre-fetched beliefs to avoid re-querying on every tick
    cached_beliefs = beliefs || []

    [
      curiosity_impulse(cached_beliefs, impulse_state, now),
      reflection_impulse(cached_beliefs, impulse_state, now),
      learning_impulse(agent, impulse_state, now),
      investigation_impulse(agent, impulse_state, now),
      self_improve_impulse(agent, impulse_state, now)
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
      last_reflection_at: nil,
      last_learning_at: nil,
      last_investigation_at: nil,
      last_self_improve_at: nil
    }
  end

  defp curiosity_impulse(beliefs, impulse_state, now) do
    if on_cooldown?(impulse_state.last_curiosity_at, now, @curiosity_cooldown_seconds) do
      nil
    else
      score = curiosity_score(beliefs)

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

  defp reflection_impulse(beliefs, impulse_state, now) do
    if on_cooldown?(impulse_state.last_reflection_at, now, @reflection_cooldown_seconds) do
      nil
    else
      score = reflection_score(beliefs)

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

  defp self_improve_impulse(agent, impulse_state, now) do
    if on_cooldown?(impulse_state.last_self_improve_at, now, @self_improve_cooldown_seconds) do
      nil
    else
      score = self_improve_score(agent)

      if score > 0.0 do
        %{
          id: "impulse:self_improve",
          statement: "I should improve my own code based on detected patterns",
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
      else
        nil
      end
    end
  end

  defp investigation_impulse(agent, impulse_state, now) do
    if on_cooldown?(impulse_state.last_investigation_at, now, @investigation_cooldown_seconds) do
      nil
    else
      score = investigation_score(agent)

      if score > 0.0 do
        %{
          id: "impulse:investigation",
          statement: "I should investigate one of my open questions",
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
      else
        nil
      end
    end
  end

  defp learning_impulse(agent, impulse_state, now) do
    if on_cooldown?(impulse_state.last_learning_at, now, @learning_cooldown_seconds) do
      nil
    else
      score = learning_score(agent)

      if score > 0.0 do
        %{
          id: "impulse:learning",
          statement: "I should research a queued topic and learn something new",
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
      else
        nil
      end
    end
  end

  defp on_cooldown?(nil, _now, _seconds), do: false

  defp on_cooldown?(last_at, now, seconds) do
    DateTime.diff(now, last_at, :second) < seconds
  end

  defp curiosity_score(beliefs) do
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

  defp self_improve_score(agent) do
    case ImprovementQueue.next(agent) do
      nil -> 0.0
      _opportunity -> 0.8
    end
  rescue
    _ -> 0.0
  end

  defp investigation_score(agent) do
    questions = Questions.list_investigatable_questions(agent, limit: 5)

    case length(questions) do
      0 -> 0.0
      n -> min(0.85, 0.4 + n * 0.1)
    end
  rescue
    _ -> 0.0
  end

  defp learning_score(agent) do
    case Autonomy.get_active_session(agent) do
      nil ->
        0.2

      session ->
        pending = Autonomy.count_pending_topics(session)
        if pending > 0, do: min(0.8, 0.3 + pending * 0.1), else: 0.1
    end
  rescue
    _ -> 0.0
  end

  defp reflection_score(beliefs) do
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
