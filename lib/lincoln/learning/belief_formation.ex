# Self-created by Lincoln for adaptive belief formation and metacognitive awareness
# This module implements confidence scoring and belief quality assessment

defmodule Lincoln.Learning.BeliefFormation do
  @moduledoc """
  Implements adaptive confidence scoring and metacognitive awareness for belief formation.
  Tracks when beliefs are formed with insufficient evidence versus high confidence,
  and adjusts confidence based on topic complexity and uncertainty patterns.
  """

  alias Lincoln.Core.{Belief, Context}
  alias Lincoln.Learning.TopicAnalysis

  @confidence_threshold 0.7
  @evidence_minimum 3
  @uncertainty_decay 0.85
  @metacognitive_flags [:insufficient_evidence, :high_uncertainty, :conflicting_sources, :novel_domain]

  defstruct [
    :topic,
    :evidence_count,
    :base_confidence,
    :adjusted_confidence,
    :uncertainty_factors,
    :metacognitive_flags,
    :formation_context,
    :revision_history
  ]

  def assess_belief_formation(belief, context, evidence_sources) do
    %__MODULE__{
      topic: belief.topic,
      evidence_count: length(evidence_sources),
      base_confidence: belief.confidence || 0.5,
      formation_context: context,
      revision_history: []
    }
    |> calculate_uncertainty_factors(evidence_sources)
    |> apply_topic_complexity_adjustment(belief.topic)
    |> identify_metacognitive_flags()
    |> adjust_confidence()
  end

  def update_belief_confidence(belief_formation, new_evidence) do
    updated_evidence_count = belief_formation.evidence_count + length(new_evidence)
    
    belief_formation
    |> Map.put(:evidence_count, updated_evidence_count)
    |> calculate_uncertainty_factors(new_evidence)
    |> update_metacognitive_flags()
    |> adjust_confidence()
    |> track_revision()
  end

  defp calculate_uncertainty_factors(formation, evidence_sources) do
    uncertainty_factors = %{
      evidence_quality: assess_evidence_quality(evidence_sources),
      source_diversity: calculate_source_diversity(evidence_sources),
      temporal_consistency: check_temporal_consistency(evidence_sources),
      conflicting_evidence: detect_conflicts(evidence_sources)
    }

    Map.put(formation, :uncertainty_factors, uncertainty_factors)
  end

  defp apply_topic_complexity_adjustment(formation, topic) do
    complexity_modifier = case TopicAnalysis.get_topic_complexity(topic) do
      :simple -> 1.0
      :moderate -> 0.9
      :complex -> 0.8
      :highly_complex -> 0.7
      :unknown -> 0.6
    end

    adjusted_confidence = formation.base_confidence * complexity_modifier
    Map.put(formation, :adjusted_confidence, adjusted_confidence)
  end

  defp identify_metacognitive_flags(formation) do
    flags = []
    |> maybe_add_flag(:insufficient_evidence, formation.evidence_count < @evidence_minimum)
    |> maybe_add_flag(:high_uncertainty, high_uncertainty?(formation))
    |> maybe_add_flag(:conflicting_sources, conflicting_sources?(formation))
    |> maybe_add_flag(:novel_domain, novel_domain?(formation))

    Map.put(formation, :metacognitive_flags, flags)
  end

  defp adjust_confidence(formation) do
    confidence_adjustments = [
      evidence_adjustment(formation),
      uncertainty_adjustment(formation),
      metacognitive_adjustment(formation)
    ]

    final_confidence = formation.adjusted_confidence
    |> apply_adjustments(confidence_adjustments)
    |> clamp_confidence()

    Map.put(formation, :adjusted_confidence, final_confidence)
  end

  defp evidence_adjustment(formation) do
    case formation.evidence_count do
      count when count < 2 -> -0.3
      count when count < @evidence_minimum -> -0.15
      count when count >= 5 -> 0.1
      _ -> 0.0
    end
  end

  defp uncertainty_adjustment(formation) do
    uncertainty_score = formation.uncertainty_factors
    |> Map.values()
    |> Enum.map(fn
      val when is_number(val) -> val
      _ -> 0.5
    end)
    |> Enum.sum()
    |> Kernel./(4)  # Average across 4 factors

    # Higher uncertainty reduces confidence
    (0.5 - uncertainty_score) * 0.4
  end

  defp metacognitive_adjustment(formation) do
    penalty = formation.metacognitive_flags
    |> Enum.map(&flag_penalty/1)
    |> Enum.sum()

    -penalty
  end

  defp apply_adjustments(base_confidence, adjustments) do
    Enum.reduce(adjustments, base_confidence, &+/2)
  end

  defp clamp_confidence(confidence) do
    confidence
    |> max(0.1)
    |> min(0.95)
  end

  # Quality assessment functions
  defp assess_evidence_quality(sources) do
    if Enum.empty?(sources) do
      0.0
    else
      sources
      |> Enum.map(&rate_source_quality/1)
      |> Enum.sum()
      |> Kernel./(length(sources))
    end
  end

  defp rate_source_quality(source) do
    # Rate based on source characteristics
    base_quality = 0.5
    
    base_quality
    |> adjust_for_source_type(source)
    |> adjust_for_recency(source)
    |> adjust_for_depth(source)
  end

  defp adjust_for_source_type(quality, source) do
    case Map.get(source, :type, :unknown) do
      :primary_research -> quality + 0.3
      :expert_analysis -> quality + 0.2
      :documentation -> quality + 0.1
      :discussion -> quality
      :speculation -> quality - 0.2
      _ -> quality
    end
  end

  defp adjust_for_recency(quality, source) do
    case Map.get(source, :timestamp) do
      nil -> quality
      timestamp ->
        hours_old = DateTime.diff(DateTime.utc_now(), timestamp, :hour)
        if hours_old < 24, do: quality + 0.1, else: quality
    end
  end

  defp adjust_for_depth(quality, source) do
    content_length = source
    |> Map.get(:content, "")
    |> String.length()

    cond do
      content_length > 500 -> quality + 0.1
      content_length < 100 -> quality - 0.1
      true -> quality
    end
  end

  defp calculate_source_diversity(sources) do
    if length(sources) < 2 do
      0.0
    else
      unique_types = sources
      |> Enum.map(&Map.get(&1, :type, :unknown))
      |> Enum.uniq()
      |> length()

      unique_types / length(sources)
    end
  end

  defp check_temporal_consistency(sources) do
    timestamps = sources
    |> Enum.map(&Map.get(&1, :timestamp))
    |> Enum.filter(&(&1 != nil))

    if length(timestamps) < 2 do
      0.5
    else
      time_span = DateTime.diff(Enum.max(timestamps), Enum.min(timestamps), :hour)
      # More consistent if sources are from similar time periods
      if time_span < 48, do: 0.8, else: 0.4
    end
  end

  defp detect_conflicts(sources) do
    # Simple conflict detection based on sentiment or explicit disagreement markers
    sentiments = sources
    |> Enum.map(&extract_sentiment/1)
    |> Enum.filter(&(&1 != :neutral))

    if Enum.empty?(sentiments) do
      0.0
    else
      positive_count = Enum.count(sentiments, &(&1 == :positive))
      negative_count = Enum.count(sentiments, &(&1 == :negative))
      
      conflict_ratio = min(positive_count, negative_count) / max(positive_count + negative_count, 1)
      conflict_ratio
    end
  end

  defp extract_sentiment(source) do
    content = Map.get(source, :content, "")
    
    cond do
      String.contains?(content, ["disagree", "incorrect", "wrong", "false"]) -> :negative
      String.contains?(content, ["agree", "correct", "right", "true", "confirms"]) -> :positive
      true -> :neutral
    end
  end

  # Flag checking functions
  defp high_uncertainty?(formation) do
    avg_uncertainty = formation.uncertainty_factors
    |> Map.values()
    |> Enum.sum()
    |> Kernel./(4)

    avg_uncertainty > 0.6
  end

  defp conflicting_sources?(formation) do
    formation.uncertainty_factors.conflicting_evidence > 0.4
  end

  defp novel_domain?(formation) do
    # Check if this topic has few existing beliefs
    case TopicAnalysis.get_topic_belief_count(formation.topic) do
      count when count < 3 -> true
      _ -> false
    end
  end

  defp flag_penalty(flag) do
    case flag do
      :insufficient_evidence -> 0.2
      :high_uncertainty -> 0.15
      :conflicting_sources -> 0.1
      :novel_domain -> 0.05
    end
  end

  defp maybe_add_flag(flags, flag, true), do: [flag | flags]
  defp maybe_add_flag(flags, _flag, false), do: flags

  defp update_metacognitive_flags(formation) do
    identify_metacognitive_flags(formation)
  end

  defp track_revision(formation) do
    revision = %{
      timestamp: DateTime.utc_now(),
      confidence_before: formation.base_confidence,
      confidence_after: formation.adjusted_confidence,
      evidence_count: formation.evidence_count
    }

    updated_history = [revision | formation.revision_history]
    Map.put(formation, :revision_history, updated_history)
  end

  # Public API for metacognitive queries
  def get_low_confidence_beliefs(min_threshold \\ 0.4) do
    # Would integrate with belief storage to find beliefs below threshold
    {:ok, "Query implementation needed - requires belief storage integration"}
  end

  def get_beliefs_with_insufficient_evidence do
    # Would find beliefs flagged with insufficient evidence
    {:ok, "Query implementation needed - requires belief storage integration"}
  end

  def suggest_topics_for_deeper_exploration do
    # Would analyze uncertainty patterns to suggest research priorities
    {:ok, "Analysis implementation needed - requires topic tracking integration"}
  end

  def confidence_trend_analysis(topic) do
    # Would analyze how confidence in a topic has evolved over time
    {:ok, "Trend analysis implementation needed - requires historical data"}
  end
end