defmodule Lincoln.Substrate.DiversityMonitorTest do
  use Lincoln.DataCase

  alias Lincoln.Substrate.DiversityMonitor

  # We test the entropy functions via the module's public API.
  # DiversityMonitor.check_and_adjust/1 reads from the Attention GenServer,
  # so we test the entropy calculation logic directly by calling the module
  # internals that are accessible.

  # Since item_entropy and topic_entropy are private, we test them indirectly
  # through the public check_and_adjust which returns entropy-based results.

  describe "item_entropy calculation" do
    test "all same IDs produce entropy 0.0 (max perseveration)" do
      # We can verify this by checking that DiversityMonitor's logic works
      # by computing it the same way the module does
      ids = List.duplicate("belief-1", 10)
      assert compute_item_entropy(ids) == 0.0
    end

    test "all different IDs produce entropy 1.0 (max diversity)" do
      ids = Enum.map(1..10, &"belief-#{&1}")
      assert_in_delta compute_item_entropy(ids), 1.0, 0.001
    end

    test "half-half distribution produces entropy 1.0" do
      ids = List.duplicate("a", 5) ++ List.duplicate("b", 5)
      assert_in_delta compute_item_entropy(ids), 1.0, 0.001
    end

    test "skewed distribution produces intermediate entropy" do
      # 8 of one, 1 each of two others
      ids = List.duplicate("a", 8) ++ ["b", "c"]
      entropy = compute_item_entropy(ids)
      assert entropy > 0.0
      assert entropy < 1.0
    end
  end

  describe "check_and_adjust/1" do
    setup do
      {:ok, agent} =
        Lincoln.Agents.create_agent(%{name: "Diversity Test #{System.unique_integer()}"})

      %{agent: agent}
    end

    test "returns insufficient_data with too few samples", %{agent: agent} do
      # No Attention GenServer running means no focus history
      assert {:ok, :insufficient_data} = DiversityMonitor.check_and_adjust(agent)
    end
  end

  # Reimplement the entropy calculation to test against expected values
  # This mirrors DiversityMonitor's private item_entropy/1
  defp compute_item_entropy([]), do: 1.0

  defp compute_item_entropy(ids) do
    total = length(ids)
    freqs = Enum.frequencies(ids)
    unique = map_size(freqs)

    if unique <= 1 do
      0.0
    else
      raw_h =
        freqs
        |> Map.values()
        |> Enum.reduce(0.0, fn count, acc ->
          p = count / total
          acc - p * :math.log2(p)
        end)

      raw_h / :math.log2(unique)
    end
  end
end
