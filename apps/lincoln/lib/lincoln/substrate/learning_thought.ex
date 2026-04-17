defmodule Lincoln.Substrate.LearningThought do
  @moduledoc """
  Substrate-native learning execution — extracted from AutonomousLearningWorker.

  Runs a single learning cycle: pick a topic, research it, form beliefs,
  queue discovered topics. Called by the Thought process when the `:learning`
  impulse wins the Attention competition.
  """

  alias Lincoln.{Autonomy, Cognition, Memory}
  alias Lincoln.Autonomy.Research

  require Logger

  @max_topic_depth 5

  @doc """
  Execute one learning cycle for the agent.

  Requires an active learning session. Returns {:ok, summary} or {:error, reason}.
  """
  def execute(agent) do
    case Autonomy.get_active_session(agent) do
      nil ->
        {:ok, "No active learning session — nothing to learn"}

      session ->
        execute_cycle(agent, session)
    end
  end

  defp execute_cycle(agent, session) do
    llm = Application.get_env(:lincoln, :llm_adapter, Lincoln.Adapters.LLM.Anthropic)

    case pick_topic(session) do
      nil ->
        {:ok, "No topics queued — learning idle"}

      topic ->
        research_and_learn(agent, session, topic, llm)
    end
  end

  defp pick_topic(session) do
    case Autonomy.get_next_topic(session) do
      nil ->
        nil

      topic ->
        if topic.depth > @max_topic_depth do
          Autonomy.skip_topic(topic, "Max depth exceeded")
          pick_topic(session)
        else
          topic
        end
    end
  end

  defp research_and_learn(agent, session, topic, llm) do
    {:ok, _topic} = Autonomy.start_topic(topic)

    case Research.research_topic(agent, session, topic, llm: llm) do
      {:ok, result} ->
        learn_from_research(agent, session, topic, result)
        queue_discovered_topics(agent, session, topic, result.related_topics)

        {:ok, _} =
          Autonomy.complete_topic(
            topic,
            length(result.facts),
            count_beliefs_formed(result.facts),
            length(result.related_topics)
          )

        Autonomy.increment_session(session, :topics_explored)

        summary =
          "Researched '#{topic.topic}': #{length(result.facts)} facts, " <>
            "#{length(result.related_topics)} related topics discovered"

        Logger.info("[LearningThought] #{summary}")
        {:ok, summary}

      {:error, :already_fetched} ->
        Autonomy.skip_topic(topic, "URL already fetched")
        {:ok, "Topic '#{topic.topic}' already researched — skipped"}

      {:error, reason} ->
        Autonomy.fail_topic(topic, inspect(reason))
        {:error, "Research failed for '#{topic.topic}': #{inspect(reason)}"}
    end
  end

  defp learn_from_research(agent, session, topic, result) do
    result.facts
    |> Enum.filter(fn f -> (f["confidence"] || 0.5) >= 0.6 end)
    |> Enum.each(fn fact ->
      case Cognition.form_belief(
             agent,
             fact["fact"],
             "observation",
             evidence: "Learned from #{result.url} while researching #{topic.topic}",
             confidence: fact["confidence"] || 0.7
           ) do
        {:ok, belief} ->
          Autonomy.increment_session(session, :beliefs_formed)

          Logger.debug(
            "[LearningThought] Formed belief: #{String.slice(belief.statement, 0, 80)}"
          )

        _ ->
          :ok
      end
    end)

    {:ok, _memory} =
      Memory.record_observation(
        agent,
        "Researched '#{topic.topic}': #{result.summary}",
        importance: 6,
        source_context: %{
          url: result.url,
          title: result.title,
          topic_id: topic.id,
          session_id: session.id
        }
      )

    Autonomy.increment_session(session, :memories_created)
  end

  defp queue_discovered_topics(agent, session, parent_topic, related_topics) do
    Enum.each(related_topics, fn topic_text ->
      Autonomy.queue_discovered_topic(
        agent,
        session,
        topic_text,
        parent_topic,
        max_depth: @max_topic_depth
      )
    end)
  end

  defp count_beliefs_formed(facts) do
    Enum.count(facts, fn f -> (f["confidence"] || 0.5) >= 0.6 end)
  end
end
