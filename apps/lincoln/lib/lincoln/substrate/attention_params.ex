defmodule Lincoln.Substrate.AttentionParams do
  @moduledoc """
  Attention parameter presets and validation.

  Parameters define the agent's "cognitive style":
  - novelty_weight: how much to prefer new/unexplored beliefs
  - focus_momentum: how strongly to continue with current focus
  - interrupt_threshold: score required to interrupt current focus
  - boredom_decay: how quickly interest in a topic decays
  - depth_preference: preference for deep vs broad exploration
  """

  @doc "Focused cognitive style — stays on topic, resists distraction."
  def focused do
    %{
      novelty_weight: 0.2,
      focus_momentum: 0.8,
      interrupt_threshold: 0.8,
      boredom_decay: 0.05,
      depth_preference: 0.8
    }
  end

  @doc "Butterfly cognitive style — jumps between topics, highly novel-seeking."
  def butterfly do
    %{
      novelty_weight: 0.8,
      focus_momentum: 0.2,
      interrupt_threshold: 0.3,
      boredom_decay: 0.3,
      depth_preference: 0.2
    }
  end

  @doc "ADHD-like cognitive style — low baseline, high momentum when engaged, large interrupts."
  def adhd_like do
    %{
      novelty_weight: 0.5,
      focus_momentum: 0.9,
      interrupt_threshold: 0.9,
      boredom_decay: 0.4,
      depth_preference: 0.6
    }
  end

  @doc "Default balanced cognitive style."
  def default do
    %{
      novelty_weight: 0.3,
      focus_momentum: 0.5,
      interrupt_threshold: 0.7,
      boredom_decay: 0.1,
      depth_preference: 0.5
    }
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
