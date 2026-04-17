defmodule Lincoln.Substrate.AttentionParams do
  @moduledoc """
  Attention parameter presets and validation.

  Parameters define the agent's "cognitive style":
  - novelty_weight: how much to prefer new/unexplored beliefs
  - focus_momentum: how strongly to continue with current focus
  - interrupt_threshold: score required to interrupt current focus
  - boredom_decay: how quickly interest in a topic decays
  - depth_preference: preference for deep vs broad exploration
  - thought_type_weights: probability distribution over thought types
  """

  @thought_types ~w(elaborate critique connect abstract question)a

  @doc "Focused cognitive style — stays on topic, goes deep."
  def focused do
    %{
      novelty_weight: 0.2,
      focus_momentum: 0.8,
      interrupt_threshold: 0.8,
      boredom_decay: 0.05,
      depth_preference: 0.8,
      thought_type_weights: %{
        elaborate: 0.4,
        critique: 0.3,
        connect: 0.1,
        abstract: 0.1,
        question: 0.1
      }
    }
  end

  @doc "Butterfly cognitive style — jumps between topics, seeks connections."
  def butterfly do
    %{
      novelty_weight: 0.8,
      focus_momentum: 0.2,
      interrupt_threshold: 0.3,
      boredom_decay: 0.3,
      depth_preference: 0.2,
      thought_type_weights: %{
        elaborate: 0.1,
        critique: 0.1,
        connect: 0.4,
        abstract: 0.2,
        question: 0.2
      }
    }
  end

  @doc "ADHD-like cognitive style — high momentum when engaged, questions when bored."
  def adhd_like do
    %{
      novelty_weight: 0.5,
      focus_momentum: 0.9,
      interrupt_threshold: 0.9,
      boredom_decay: 0.4,
      depth_preference: 0.6,
      thought_type_weights: %{
        elaborate: 0.2,
        critique: 0.15,
        connect: 0.25,
        abstract: 0.15,
        question: 0.25
      }
    }
  end

  @doc "Default balanced cognitive style."
  def default do
    %{
      novelty_weight: 0.3,
      focus_momentum: 0.5,
      interrupt_threshold: 0.7,
      boredom_decay: 0.1,
      depth_preference: 0.5,
      thought_type_weights: %{
        elaborate: 0.25,
        critique: 0.2,
        connect: 0.2,
        abstract: 0.15,
        question: 0.2
      }
    }
  end

  @doc "Select a thought type using weighted random selection from the preset."
  def select_thought_type(params) do
    weights = Map.get(params, :thought_type_weights) || Map.get(params, "thought_type_weights")

    if weights do
      weighted_random(weights)
    else
      Enum.random(@thought_types)
    end
  end

  defp weighted_random(weights) when is_map(weights) do
    total = weights |> Map.values() |> Enum.sum()

    if total == 0 do
      Enum.random(@thought_types)
    else
      pick_weighted(weights, :rand.uniform() * total)
    end
  end

  defp pick_weighted(weights, roll) do
    result =
      Enum.reduce_while(weights, 0.0, fn {type, weight}, acc ->
        new_acc = acc + weight
        if new_acc >= roll, do: {:halt, type}, else: {:cont, new_acc}
      end)

    if is_atom(result), do: result, else: :elaborate
  end

  @float_params ~w(novelty_weight focus_momentum interrupt_threshold boredom_decay depth_preference)a

  @doc """
  Validate attention parameters.
  Returns {:ok, params} or {:error, errors}.
  """
  def validate(params) do
    errors =
      Enum.reduce(@float_params, [], fn param, acc ->
        case validate_param_value(param, Map.get(params, param)) do
          nil -> acc
          error -> [{param, error} | acc]
        end
      end)

    if errors == [] do
      {:ok, params}
    else
      {:error, errors}
    end
  end

  defp validate_param_value(_param, nil), do: "is required"

  defp validate_param_value(param, val) when param in @float_params do
    unless is_float(val) and val >= 0.0 and val <= 1.0,
      do: "must be a float between 0.0 and 1.0"
  end

  @doc "Merge custom params over the default preset."
  def merge(custom_params) do
    Map.merge(default(), custom_params)
  end
end
