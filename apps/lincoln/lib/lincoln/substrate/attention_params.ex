defmodule Lincoln.Substrate.AttentionParams do
  @moduledoc """
  Attention parameter presets and validation.

  Parameters define the agent's "cognitive style":
  - novelty_weight: how much to prefer new/unexplored beliefs
  - focus_momentum: how strongly to continue with current focus
  - interrupt_threshold: score required to interrupt current focus
  - boredom_decay: how quickly interest in a topic decays
  - depth_preference: preference for deep vs broad exploration
  - tick_interval_ms: tick rate in milliseconds
  """

  @doc "Focused cognitive style — stays on topic, resists distraction."
  def focused do
    %{
      novelty_weight: 0.2,
      focus_momentum: 0.8,
      interrupt_threshold: 0.8,
      boredom_decay: 0.05,
      depth_preference: 0.8,
      tick_interval_ms: 5_000
    }
  end

  @doc "Butterfly cognitive style — jumps between topics, highly novel-seeking."
  def butterfly do
    %{
      novelty_weight: 0.8,
      focus_momentum: 0.2,
      interrupt_threshold: 0.3,
      boredom_decay: 0.3,
      depth_preference: 0.2,
      tick_interval_ms: 5_000
    }
  end

  @doc "ADHD-like cognitive style — low baseline, high momentum when engaged, large interrupts."
  def adhd_like do
    %{
      novelty_weight: 0.5,
      focus_momentum: 0.9,
      interrupt_threshold: 0.9,
      boredom_decay: 0.4,
      depth_preference: 0.6,
      tick_interval_ms: 5_000
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
      tick_interval_ms: 5_000
    }
  end

  @float_params ~w(novelty_weight focus_momentum interrupt_threshold boredom_decay depth_preference)a
  @required_params @float_params ++ [:tick_interval_ms]

  @doc """
  Validate attention parameters.
  Returns {:ok, params} or {:error, errors}.
  """
  def validate(params) do
    errors =
      Enum.reduce(@required_params, [], fn param, acc ->
        case Map.get(params, param) do
          nil ->
            [{param, "is required"} | acc]

          val when param == :tick_interval_ms ->
            if is_integer(val) and val >= 1_000 and val <= 60_000 do
              acc
            else
              [{param, "must be an integer between 1000 and 60000"} | acc]
            end

          val when param in @float_params ->
            if is_float(val) and val >= 0.0 and val <= 1.0 do
              acc
            else
              [{param, "must be a float between 0.0 and 1.0"} | acc]
            end
        end
      end)

    if errors == [] do
      {:ok, params}
    else
      {:error, errors}
    end
  end

  @doc "Merge custom params over the default preset."
  def merge(custom_params) do
    Map.merge(default(), custom_params)
  end
end
