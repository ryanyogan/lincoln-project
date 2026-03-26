# Self-created by Lincoln for adaptive belief formation and metacognitive awareness
# This module implements confidence scoring and belief quality assessment
# Self-modified: Enhanced with active belief confidence tracking and uncertainty quantification for improved metacognitive reasoning

defmodule Lincoln.Learning.BeliefFormation do
  @moduledoc """
  Implements adaptive confidence scoring and metacognitive awareness for belief formation.
  Tracks when beliefs are formed with insufficient evidence versus high confidence,
  and adjusts confidence based on topic complexity and uncertainty patterns.
  Enhanced with active tracking and real-time uncertainty quantification.
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
    :revision_history,
    :confidence_trajectory,
    :uncertainty_score,
    :knowledge_quality_rating
  ]

  # Active confidence tracking state
  @belief_confidence_registry :belief_confidence_registry

  def start_confidence_tracking do
    case :ets.info(@belief_confidence_registry) do
      :undefined -> 
        :ets.new(@belief_confidence_registry, [:named_table, :public, :set])
        {:ok, :started}
      _ -> 
        {:ok, :already_running}
    end
  end

  def assess_belief_formation(belief, context, evidence_sources) do
    start_confidence_tracking()
    
    formation = %__MODULE__{
      topic: belief.topic,
      evidence_count: length(evidence_sources),
      base_confidence: belief.confidence || 0.5,
      formation_context: context,
      revision_history: [],
      confidence_trajectory: [{DateTime.utc_now(), belief.confidence || 0.5}]
    }
    |> calculate_uncertainty_factors(evidence_sources)
    |> apply_topic_complexity_adjustment(belief.topic)
    |> identify_metacognitive_flags()
    |> adjust_confidence()
    |> calculate_uncertainty_score()
    |> assign_knowledge_quality_rating()

    # Store in active tracking registry
    store_belief_confidence(belief.topic, formation)
    
    formation
  end

  def update_belief_confidence(belief_formation, new_evidence) do
    updated_evidence_count = belief_formation.evidence_count + length(new_evidence)
    
    updated_formation = belief_formation
    |> Map.put(:evidence_count, updated_evidence_count)
    |> calculate_uncertainty_factors(new_evidence)
    |> update_metacognitive_flags()
    |> adjust_confidence()
    |> calculate_uncertainty_score()
    |> assign_knowledge_quality_rating()
    |> track_revision()
    |> update_confidence_trajectory()

    # Update active tracking
    store_belief_confidence(belief_formation.topic, updated_formation)
    
    updated_formation
  end

  def get_current_confidence(topic) do
    case :ets.lookup(@belief_confidence_registry, topic) do
      [{^topic, formation}] -> 
        {:ok, formation.adjusted_confidence, formation.uncertainty_score}
      [] -> 
        {:error, :topic_not_found}
    end
  end

  def get_knowledge_quality_summary do
    start_confidence_tracking()
    
    all_beliefs = :ets.tab2list(@belief_confidence_registry)
    
    if Enum.empty?(all_beliefs) do
      %{
        total_beliefs: 0,
        high_confidence: 0,
        medium_confidence: 0,
        low_confidence: 0,
        average_uncertainty: 0.0,
        quality_distribution: %{}
      }
    else
      formations = Enum.map(all_beliefs, fn {_topic, formation} -> formation end)
      
      %{
        total_beliefs: length(formations),
        high_confidence: count_by_confidence(formations, 0.7, 1.0),
        medium_confidence: count_by_confidence(formations, 0.4, 0.7),
        low_confidence: count_by_confidence(formations, 0.0, 0.4),
        average_uncertainty: calculate_average_uncertainty(formations),
        quality_distribution: calculate_quality_distribution(formations),
        problematic_beliefs: identify_problematic_beliefs(formations)
      }
    end
  end

  def quantify_uncertainty_for_topic(topic) do
    case get_current_confidence(topic) do
      {:ok, confidence, uncertainty_score} ->
        uncertainty_breakdown = case :ets.lookup(@belief_confidence_registry, topic) do
          [{^topic, formation}] -> 
            %{
              evidence_sufficiency: evidence_sufficiency_score(formation),
              source_reliability: formation.uncertainty_factors.evidence_quality,
              topic_complexity: topic_complexity_uncertainty(formation.topic),
              temporal_stability: formation.uncertainty_factors.temporal_consistency,
              conflict_level: formation.uncertainty_factors.conflicting_evidence,
              overall_uncertainty: uncertainty_score,
              confidence_stability: calculate_confidence_stability(formation)
            }
          [] -> %{}
        end
        
        {:ok, uncertainty_breakdown}
      error -> error
    end
  end

  def get_beliefs_requiring_attention(urgency_threshold \\ 0.6) do
    start_confidence_tracking()
    
    :ets.tab2list(@belief_confidence_registry)
    |> Enum.map(fn {topic, formation} -> {topic, formation} end)
    |> Enum.filter(fn {_topic, formation} -> 
      needs_attention?(formation, urgency_threshold)
    end)
    |> Enum.map(fn {topic, formation} ->
      %{
        topic: topic,
        issues: identify_issues(formation),
        confidence: formation.adjusted_confidence,
        uncertainty: formation.uncertainty_score,
        recommendation: generate_recommendation(formation)
      }
    end)
  end

  defp store_belief_confidence(topic, formation) do
    :ets.insert(@belief_confidence_registry, {topic, formation})
  end

  defp calculate_uncertainty_score(formation) do
    uncertainty_components = [
      evidence_uncertainty(formation),
      source_uncertainty(formation),
      temporal_uncertainty(formation),
      conflict_uncertainty(formation),
      metacognitive_uncertainty(formation)
    ]
    
    overall_uncertainty = uncertainty_components
    |> Enum.sum()
    |> Kernel./(length(uncertainty_components))
    
    Map.put(formation, :uncertainty_score, overall_uncertainty)
  end

  defp assign_knowledge_quality_rating(formation) do
    rating = cond do
      formation.adjusted_confidence >= 0.8 && formation.uncertainty_score <= 0.3 -> :high_quality
      formation.adjusted_confidence >= 0.6 && formation.uncertainty_score <= 0.5 -> :good_quality
      formation.adjusted_confidence >= 0.4 && formation.uncertainty_score <= 0.7 -> :moderate_quality
      formation.adjusted_confidence >= 0.2 -> :low_quality
      true -> :unreliable
    end
    
    Map.put(formation, :knowledge_quality_rating, rating)
  end

  defp update_confidence_trajectory(formation) do
    new_point = {DateTime.utc_now(), formation.adjusted_confidence}
    updated_trajectory = [new_point | formation.confidence_trajectory]
    
    # Keep only last 10 points to avoid memory bloat
    trimmed_trajectory = Enum.take(updated_trajectory, 10)
    
    Map.put(formation, :confidence_trajectory, trimmed_trajectory)
  end

  defp evidence_uncertainty(formation) do
    case formation.evidence_count do
      0 -> 1.0
      1 -> 0.8
      2 -> 0.6
      count when count < @evidence_minimum -> 0.5
      count when count >= 5 -> 0.2
      _ -> 0.3
    end
  end

  defp source_uncertainty(formation) do
    1.0 - formation.uncertainty_factors.evidence_quality
  end

  defp temporal_uncertainty(formation) do
    1.0 - formation.uncertainty_factors.temporal_consistency
  end

  defp conflict_uncertainty(formation) do
    formation.uncertainty_factors.conflicting_evidence
  end

  defp metacognitive_uncertainty(formation) do
    flag_count = length(formation.metacognitive_flags)
    min(flag_count * 0.2, 1.0)
  end

  defp evidence_sufficiency_score(formation) do
    case formation.evidence_count do
      count when count >= @evidence_minimum -> 0.9
      count when count >= 2 -> 0.6
      1 -> 0.3
      0 -> 0.0
    end
  end

  defp topic_complexity_uncertainty(topic) do
    case TopicAnalysis.get_topic_complexity(topic) do
      :simple -> 0.1
      :moderate -> 0.3
      :complex -> 0.5
      :highly_complex -> 0.7
      :unknown -> 0.9
    end
  end

  defp calculate_confidence_stability(formation) do
    if length(formation.confidence_trajectory) < 2 do
      0.5
    else
      confidences = Enum.map(formation.confidence_trajectory, fn {_time, conf} -> conf end)
      variance = calculate_variance(confidences)
      max(0.0, 1.0 - variance * 2)
    end
  end

  defp calculate_variance(values) do
    if length(values) < 2 do
      0.0
    else
      mean = Enum.sum(values) / length(values)
      sum_squared_diff = values
      |> Enum.map(fn x -> :math.pow(x - mean, 2) end)
      |> Enum.sum()
      
      sum_squared_diff / length(values)
    end
  end

  defp count_by_confidence(formations, min_conf, max_conf) do
    formations
    |> Enum.count(fn formation -> 
      conf = formation.adjusted_confidence
      conf >= min_conf && conf < max_conf
    end)
  end

  defp calculate_average_uncertainty(formations) do
    if Enum.empty?(formations) do
      0.0
    else
      formations
      |> Enum.map(& &1.uncertainty_score)
      |> Enum.sum()
      |> Kernel./(length(formations))
    end
  end

  defp calculate_quality_distribution(formations) do
    formations
    |> Enum.group_by(& &1.knowledge_quality_rating)
    |> Enum.map(fn {quality, beliefs} -> {quality, length(beliefs)} end)
    |> Enum.into(%{})
  end

  defp identify_problematic_beliefs(formations) do
    formations
    |> Enum.filter(fn formation ->
      formation.uncertainty_score > 0.7 || 
      formation.adjusted_confidence < 0.3 ||
      :insufficient_evidence in formation.metacognitive_flags
    end)
    |> Enum.map(& &1.topic)
  end

  defp needs_attention?(formation, threshold) do
    formation.uncertainty_score >= threshold ||
    formation.adjusted_confidence <= 0.3 ||
    length(formation.metacognitive_flags) >= 2
  end

  defp identify_issues(formation) do
    issues = []
    
    issues = if formation.uncertainty_score > 0.7, do: [:high_uncertainty | issues], else: issues
    issues = if formation.adjusted_confidence < 0.3, do: [:low_confidence | issues], else: issues
    issues = if formation.evidence_count < @evidence_minimum, do: [:insufficient_evidence | issues], else: issues
    issues = if :conflicting_sources in formation.metacognitive_flags, do: [:conflicting_sources | issues], else: issues
    
    issues
  end

  defp generate_recommendation(formation) do
    cond do
      formation.evidence_count < @evidence_minimum ->
        "Gather more evidence sources to improve confidence"
      
      formation.uncertainty_factors.conflicting_evidence > 0.5 ->
        "Resolve conflicting information from sources"
      
      formation.uncertainty_factors.evidence_quality < 0.4 ->
        "Seek higher quality, more authoritative sources"
      
      :novel_domain in formation.metacognitive_flags ->
        "Build foundational understanding in this domain"
      
      true ->
        "Continue monitoring and updating as new information becomes available"
    end
  end

  # Existing helper functions remain unchanged
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

  defp apply_adjustments(base_confidence,