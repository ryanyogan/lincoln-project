defmodule Lincoln.QuestionsPipelineTest do
  use Lincoln.DataCase, async: true

  alias Lincoln.{Agents, Questions}

  describe "count_open_questions/1" do
    setup do
      {:ok, agent} = Agents.create_agent(%{name: "Count Agent #{System.unique_integer()}"})
      %{agent: agent}
    end

    test "returns correct count of open questions", %{agent: agent} do
      assert Questions.count_open_questions(agent) == 0

      {:ok, _} = Questions.ask_question(agent, "Question 1")
      {:ok, _} = Questions.ask_question(agent, "Question 2")
      {:ok, _} = Questions.ask_question(agent, "Question 3")

      assert Questions.count_open_questions(agent) == 3
    end

    test "does not count abandoned questions", %{agent: agent} do
      {:ok, q1} = Questions.ask_question(agent, "Will be abandoned")
      {:ok, _} = Questions.ask_question(agent, "Stays open")

      Questions.abandon_question(q1)

      assert Questions.count_open_questions(agent) == 1
    end

    test "does not count answered questions", %{agent: agent} do
      {:ok, q1} = Questions.ask_question(agent, "To be answered")
      {:ok, _} = Questions.ask_question(agent, "Stays open")

      Questions.create_finding(agent, q1, %{
        answer: "The answer",
        source_type: "investigation",
        confidence: 0.9
      })

      assert Questions.count_open_questions(agent) == 1
    end
  end

  describe "prune_stale_questions/2" do
    setup do
      {:ok, agent} = Agents.create_agent(%{name: "Prune Agent #{System.unique_integer()}"})
      %{agent: agent}
    end

    test "prunes old questions with times_asked <= 1", %{agent: agent} do
      # Create a question and backdate it
      {:ok, stale} = Questions.ask_question(agent, "Old forgotten question")

      stale
      |> Ecto.Changeset.change(inserted_at: DateTime.utc_now() |> DateTime.add(-31 * 86_400, :second) |> DateTime.truncate(:second))
      |> Repo.update!()

      pruned_count = Questions.prune_stale_questions(agent)
      assert pruned_count == 1

      question = Questions.get_question!(stale.id)
      assert question.status == "abandoned"
    end

    test "keeps old questions with times_asked > 1", %{agent: agent} do
      {:ok, popular} = Questions.ask_question(agent, "Frequently asked question")

      # Increment times_asked
      popular
      |> Ecto.Changeset.change(
        times_asked: 3,
        inserted_at: DateTime.utc_now() |> DateTime.add(-31 * 86_400, :second) |> DateTime.truncate(:second)
      )
      |> Repo.update!()

      pruned_count = Questions.prune_stale_questions(agent)
      assert pruned_count == 0

      question = Questions.get_question!(popular.id)
      assert question.status == "open"
    end

    test "keeps recent questions even with times_asked == 1", %{agent: agent} do
      {:ok, recent} = Questions.ask_question(agent, "Recent question")

      # This is recent (inserted today), should not be pruned
      pruned_count = Questions.prune_stale_questions(agent)
      assert pruned_count == 0

      question = Questions.get_question!(recent.id)
      assert question.status == "open"
    end

    test "respects custom stale_days option", %{agent: agent} do
      {:ok, q} = Questions.ask_question(agent, "10 day old question")

      q
      |> Ecto.Changeset.change(inserted_at: DateTime.utc_now() |> DateTime.add(-11 * 86_400, :second) |> DateTime.truncate(:second))
      |> Repo.update!()

      # With default 30 days, should not be pruned
      assert Questions.prune_stale_questions(agent) == 0

      # With 10 day threshold, should be pruned
      assert Questions.prune_stale_questions(agent, stale_days: 10) == 1
    end
  end

  describe "investigation question ordering" do
    setup do
      {:ok, agent} = Agents.create_agent(%{name: "Order Agent #{System.unique_integer()}"})
      %{agent: agent}
    end

    test "prioritizes frequently-asked questions", %{agent: agent} do
      {:ok, _rare} = Questions.ask_question(agent, "Rare question")
      {:ok, frequent} = Questions.ask_question(agent, "Frequent question")

      # Manually set times_asked
      frequent
      |> Ecto.Changeset.change(times_asked: 5)
      |> Repo.update!()

      questions = Questions.list_investigatable_questions(agent)
      assert hd(questions).id == frequent.id
    end
  end
end
