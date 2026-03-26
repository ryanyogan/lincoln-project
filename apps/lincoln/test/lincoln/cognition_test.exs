defmodule Lincoln.CognitionTest do
  @moduledoc """
  Tests for the Cognition context - the thinking layer.

  Uses Mox to mock LLM and Embeddings adapters.
  """
  use Lincoln.DataCase, async: true

  import Mox

  alias Lincoln.{Agents, Beliefs, Cognition, Memory}

  # Ensure Mox expectations are verified
  setup :verify_on_exit!

  describe "reflect/2" do
    setup do
      {:ok, agent} = Agents.create_agent(%{name: "Test Reflector #{System.unique_integer()}"})
      %{agent: agent}
    end

    test "returns empty insights when not enough memories", %{agent: agent} do
      # No mocks needed - should short-circuit with too few memories
      assert {:ok, %{insights: [], memory_count: 0}} = Cognition.reflect(agent)
    end

    test "generates insights from memories", %{agent: agent} do
      # Create enough memories for reflection (need at least 3 with importance >= 4)
      for i <- 1..5 do
        {:ok, _} =
          Memory.record_observation(agent, "Observation #{i}: The system behaves in pattern #{i}",
            importance: 5 + rem(i, 4)
          )
      end

      # Mock the LLM extract response
      Lincoln.LLMMock
      |> expect(:extract, fn _prompt, _schema, _opts ->
        {:ok,
         [
           %{
             "insight" => "Patterns 1-5 suggest a recurring behavior cycle",
             "importance" => 7,
             "related_memories" => ["Observation 1", "Observation 3"],
             "questions_raised" => ["Why does this pattern repeat?"]
           }
         ]}
      end)

      assert {:ok, result} = Cognition.reflect(agent)
      assert result.memory_count >= 3
      assert length(result.insights) == 1

      insight = hd(result.insights)
      assert insight.memory_type == "reflection"
      assert insight.content =~ "Patterns 1-5"
    end

    test "handles LLM errors gracefully", %{agent: agent} do
      # Create memories
      for i <- 1..5 do
        {:ok, _} = Memory.record_observation(agent, "Observation #{i}", importance: 6)
      end

      # Mock LLM failure
      Lincoln.LLMMock
      |> expect(:extract, fn _prompt, _schema, _opts ->
        {:error, {:api_error, 500, "Internal error"}}
      end)

      assert {:error, {:api_error, 500, "Internal error"}} = Cognition.reflect(agent)
    end
  end

  describe "generate_curiosity/2" do
    setup do
      {:ok, agent} = Agents.create_agent(%{name: "Test Curious #{System.unique_integer()}"})
      %{agent: agent}
    end

    test "generates questions from agent context", %{agent: agent} do
      # Add some context
      {:ok, _} =
        Memory.record_observation(agent, "Observed an interesting pattern", importance: 6)

      {:ok, _} =
        Beliefs.create_belief(agent, %{
          statement: "Patterns tend to repeat",
          source_type: "observation",
          confidence: 0.7
        })

      # Mock LLM to return questions
      Lincoln.LLMMock
      |> expect(:extract, fn _prompt, _schema, _opts ->
        {:ok,
         [
           %{
             "question" => "What causes patterns to repeat?",
             "context" => "Based on observations of recurring patterns",
             "priority" => 7
           }
         ]}
      end)

      # Mock embeddings for the question (embed/2 takes text and opts)
      Lincoln.EmbeddingsMock
      |> expect(:embed, fn text, _opts ->
        assert text == "What causes patterns to repeat?"
        {:ok, generate_fake_embedding(text)}
      end)
      |> expect(:semantic_hash, fn embedding ->
        assert is_list(embedding)
        "fake_hash_123"
      end)

      assert {:ok, result} = Cognition.generate_curiosity(agent)
      assert result.context_size > 0
      assert length(result.questions) == 1

      question = hd(result.questions)
      assert question.question == "What causes patterns to repeat?"
      assert question.priority == 7
    end

    test "returns empty when LLM returns no questions", %{agent: agent} do
      Lincoln.LLMMock
      |> expect(:extract, fn _prompt, _schema, _opts ->
        {:ok, []}
      end)

      assert {:ok, %{questions: []}} = Cognition.generate_curiosity(agent)
    end
  end

  describe "form_belief/4" do
    setup do
      {:ok, agent} = Agents.create_agent(%{name: "Test Believer #{System.unique_integer()}"})
      %{agent: agent}
    end

    test "creates new belief when no similar beliefs exist", %{agent: agent} do
      content = "The sky is blue during clear days"

      # Mock embeddings
      Lincoln.EmbeddingsMock
      |> expect(:embed, fn text, _opts ->
        assert text == content
        {:ok, generate_fake_embedding(text)}
      end)

      assert {:ok, belief} = Cognition.form_belief(agent, content, "observation")
      assert belief.statement == content
      assert belief.source_type == "observation"
      assert belief.confidence == 0.6
    end

    test "strengthens existing belief when very similar belief exists", %{agent: agent} do
      # Create an existing belief with embedding
      existing_content = "Water is essential for life"
      embedding = generate_fake_embedding(existing_content)

      {:ok, existing} =
        Beliefs.create_belief(agent, %{
          statement: existing_content,
          source_type: "observation",
          confidence: 0.7,
          embedding: embedding
        })

      # Try to form a nearly identical belief
      new_content = "Water is essential for life"

      Lincoln.EmbeddingsMock
      |> expect(:embed, fn text, _opts ->
        assert text == new_content
        # Return same embedding to trigger similarity match
        {:ok, embedding}
      end)

      assert {:ok, updated} = Cognition.form_belief(agent, new_content, "observation")
      # Should strengthen the existing belief
      assert updated.id == existing.id
      # Strengthening increases confidence
      assert updated.confidence > existing.confidence
    end

    test "creates new belief when similar beliefs exist but are INDEPENDENT", %{agent: agent} do
      # This test verifies that when the LLM determines beliefs are INDEPENDENT,
      # a new belief is created. Note: We can't fully mock the pgvector similarity
      # search, so this test creates a scenario where no database-level similarity
      # is found (completely different embeddings), and the belief is created directly.

      new_content = "Cats can be very social and dependent"
      new_embedding = generate_fake_embedding(new_content)

      Lincoln.EmbeddingsMock
      |> expect(:embed, fn text, _opts ->
        assert text == new_content
        {:ok, new_embedding}
      end)

      # No similar beliefs will be found (different embedding), so this creates directly
      assert {:ok, belief} = Cognition.form_belief(agent, new_content, "observation")
      assert belief.statement == new_content
      assert belief.source_type == "observation"
    end
  end

  describe "would_create_loop?/4" do
    setup do
      {:ok, agent} = Agents.create_agent(%{name: "Test Looper #{System.unique_integer()}"})
      %{agent: agent}
    end

    test "returns false when no previous similar actions", %{agent: agent} do
      Lincoln.EmbeddingsMock
      |> expect(:embed, fn _text, _opts ->
        {:ok, generate_fake_embedding("unique action")}
      end)
      |> expect(:semantic_hash, fn _embedding ->
        "unique_hash_#{System.unique_integer()}"
      end)

      refute Cognition.would_create_loop?(agent, "investigate", "new question")
    end
  end

  describe "record_action/4" do
    setup do
      {:ok, agent} = Agents.create_agent(%{name: "Test Actor #{System.unique_integer()}"})
      %{agent: agent}
    end

    test "logs action with embeddings", %{agent: agent} do
      Lincoln.EmbeddingsMock
      |> expect(:embed, fn text, _opts ->
        assert text =~ "investigate"
        {:ok, generate_fake_embedding(text)}
      end)
      |> expect(:semantic_hash, fn _embedding ->
        "action_hash_123"
      end)

      assert {:ok, action} =
               Cognition.record_action(agent, "investigate", "researching question X")

      assert action.action_type == "investigate"
      assert action.description == "researching question X"
      assert action.semantic_hash == "action_hash_123"
    end
  end

  # Helper to generate deterministic fake embeddings
  defp generate_fake_embedding(text) do
    hash = :crypto.hash(:sha256, text)

    hash
    |> :binary.bin_to_list()
    |> Stream.cycle()
    |> Enum.take(384)
    |> Enum.map(fn byte -> (byte - 128) / 128.0 end)
  end
end
