defmodule Lincoln.Goals.MethodLibraryTest do
  use Lincoln.DataCase, async: true

  alias Lincoln.{Agents, Goals.MethodLibrary}

  setup do
    {:ok, agent} = Agents.create_agent(%{name: "MethodLib #{System.unique_integer()}"})
    %{agent: agent}
  end

  describe "record/4 + find_similar/3" do
    test "round-trips a method via cosine similarity", %{agent: agent} do
      embedding = stable_embedding(0.5)

      templates = [
        %{"statement" => "Find the form", "priority" => 8},
        %{"statement" => "Fill it out", "priority" => 7}
      ]

      assert {:ok, _} = MethodLibrary.record(agent, "submit_form", templates, embedding)

      assert %{pattern: "submit_form", sub_goal_templates: returned} =
               MethodLibrary.find_similar(agent, embedding)

      assert returned == templates
    end

    test "returns nil for embeddings below the threshold", %{agent: agent} do
      stored_embedding = stable_embedding(0.5)
      different_embedding = stable_embedding(2.0)

      assert {:ok, _} =
               MethodLibrary.record(agent, "x", [%{"statement" => "x"}], stored_embedding)

      assert is_nil(MethodLibrary.find_similar(agent, different_embedding, threshold: 0.95))
    end
  end

  describe "record_usage/2" do
    test "increments success/failure counters and bumps last_used_at", %{agent: agent} do
      {:ok, method} =
        MethodLibrary.record(agent, "x", [%{"statement" => "x"}], stable_embedding(0.5))

      assert {:ok, after_success} = MethodLibrary.record_usage(method, :success)
      assert after_success.success_count == 1
      assert after_success.usage_count == 1

      assert {:ok, after_failure} = MethodLibrary.record_usage(after_success, :failure)
      assert after_failure.failure_count == 1
      assert after_failure.usage_count == 2
    end
  end

  defp stable_embedding(seed) do
    for i <- 0..383, do: :math.sin(seed + i / 100.0)
  end
end
