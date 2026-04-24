defmodule Lincoln.Substrate.InvestigationThoughtSearchTest do
  @moduledoc """
  Verifies that `InvestigationThought` consults the configured search adapter
  and folds results into the LLM prompt context. Other end-to-end behaviour
  of investigation is covered elsewhere; this file is scoped to the Phase 3
  integration surface.
  """

  use Lincoln.DataCase, async: true

  import Mox

  alias Lincoln.{Agents, Questions}
  alias Lincoln.Substrate.InvestigationThought

  setup :verify_on_exit!

  setup do
    {:ok, agent} = Agents.create_agent(%{name: "Investigation #{System.unique_integer()}"})

    {:ok, question} =
      Questions.ask_question(agent, "What is the BEAM scheduler?", priority: 8)

    %{agent: agent, question: question}
  end

  test "search adapter results appear in the LLM prompt", %{agent: agent} do
    stub(Lincoln.EmbeddingsMock, :embed, fn _text, _opts -> {:ok, fake_embedding(0.3)} end)

    expect(Lincoln.SearchClientMock, :search, fn query, _opts ->
      assert query =~ "BEAM scheduler"

      {:ok,
       [
         %{
           title: "Reductions and preemption in BEAM",
           url: "https://blog.example/beam",
           snippet: "BEAM uses reductions to preempt processes fairly..."
         }
       ]}
    end)

    expect(Lincoln.LLMMock, :extract, fn prompt, _schema, _opts ->
      assert prompt =~ "Web search results"
      assert prompt =~ "Reductions and preemption in BEAM"

      {:ok,
       %{
         "answer" => "BEAM uses preemption via reductions",
         "confidence" => 0.65,
         "reasoning" => "from search results",
         "follow_up_questions" => []
       }}
    end)

    assert {:ok, summary} = InvestigationThought.execute(agent)
    assert is_binary(summary)
  end

  test "search returning empty list does not add a section to the prompt", %{agent: agent} do
    stub(Lincoln.EmbeddingsMock, :embed, fn _text, _opts -> {:ok, fake_embedding(0.4)} end)
    expect(Lincoln.SearchClientMock, :search, fn _query, _opts -> {:ok, []} end)

    expect(Lincoln.LLMMock, :extract, fn prompt, _schema, _opts ->
      refute prompt =~ "Web search results"

      {:ok,
       %{
         "answer" => "Unknown",
         "confidence" => 0.3,
         "reasoning" => "",
         "follow_up_questions" => []
       }}
    end)

    assert {:ok, _} = InvestigationThought.execute(agent)
  end

  test "search adapter failure does not crash investigation", %{agent: agent} do
    stub(Lincoln.EmbeddingsMock, :embed, fn _text, _opts -> {:ok, fake_embedding(0.5)} end)
    expect(Lincoln.SearchClientMock, :search, fn _query, _opts -> {:error, :unreachable} end)

    expect(Lincoln.LLMMock, :extract, fn prompt, _schema, _opts ->
      refute prompt =~ "Web search results"

      {:ok,
       %{
         "answer" => "Unknown",
         "confidence" => 0.3,
         "reasoning" => "",
         "follow_up_questions" => []
       }}
    end)

    assert {:ok, _} = InvestigationThought.execute(agent)
  end

  defp fake_embedding(seed) do
    for i <- 0..383, do: :math.sin(seed + i / 100.0)
  end
end
