# Self-created by Lincoln for adaptive belief formation and metacognitive awareness
# This module implements confidence scoring and belief quality assessment
# Self-modified: Enhanced with active belief confidence tracking and uncertainty quantification for improved metacognitive reasoning
# Self-modified: Added comprehensive belief revision mechanisms and enhanced confidence scoring for better knowledge management
# Self-modified: Enhanced confidence scoring precision and added belief uncertainty tracking for better decision-making under uncertainty

defmodule Lincoln.Learning.BeliefFormation do
  @moduledoc """
  Implements adaptive confidence scoring and metacognitive awareness for belief formation.
  Tracks when beliefs are formed with insufficient evidence versus high confidence,
  and adjusts confidence based on topic complexity and uncertainty patterns.
  Enhanced with active tracking, real-time uncertainty quantification, and belief revision mechanisms.
  """

  alias Lincoln.Core.{Belief, Context}
  alias Lincoln.Learning.TopicAnalysis

  @confidence_threshold 0.7
  @evidence_minimum 3
  @uncertainty_decay 0.85
  @revision_threshold 0.4
  @contradiction_threshold 0.6
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
    :knowledge_quality_rating,
    :contradictions_detected,
    :last_revision_time,
    :revision_count,
    :evidence_sources,
    :confidence_precision_score,
    :uncertainty_components,
    :confidence_calibration_data
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
      confidence_trajectory: [{DateTime.utc_now(), belief.confidence || 0.5}],
      contradictions_detected: [],
      last_revision_time: DateTime.utc_now(),
      revision_count: 0,
      evidence_sources: evidence_sources,
      confidence_calibration_data: %{formation_time: DateTime.utc_now(), validation_events: []}
    }
    |> calculate_uncertainty_factors(evidence_sources)
    |> apply_topic_complexity_adjustment(belief.topic)
    |> identify_metacognitive_flags()
    |> adjust_confidence()
    |> calculate_uncertainty_score()
    |> calculate_detailed_uncertainty_components()
    |> calculate_confidence_precision()
    |> assign_knowledge_quality_rating()

    # Store in active tracking registry
    store_belief_confidence(belief.topic, formation)
    
    formation
  end

  def get_confidence_weighted_beliefs(confidence_threshold \\ 0.5) do
    start_confidence_tracking()
    
    :ets.tab2list(@belief_confidence_registry)
    |> Enum.map(fn {topic, formation} -> 
      %{
        topic: topic,
        confidence: formation.adjusted_confidence,
        uncertainty: formation.uncertainty_score,
        precision: formation.confidence_precision_score || 0.5,
        weight: calculate_decision_weight(formation),
        reliability_class: classify_belief_reliability(formation),
        use_for_reasoning: formation.adjusted_confidence >= confidence_threshold
      }
    end)
    |> Enum.sort_by(& &1.confidence, :desc)
  end

  def get_uncertainty_prioritized_learning_targets do
    start_confidence_tracking()
    
    :ets.tab2list(@belief_confidence_registry)
    |> Enum.map(fn {topic, formation} -> 
      learning_priority = calculate_learning_priority(formation)
      uncertainty_breakdown = formation.uncertainty_components || %{}
      
      %{
        topic: topic,
        current_confidence: formation.adjusted_confidence,
        uncertainty_score: formation.uncertainty_score,
        learning_priority: learning_priority,
        uncertainty_type: identify_primary_uncertainty_source(uncertainty_breakdown),
        evidence_gaps: identify_evidence_gaps(formation),
        recommended_action: recommend_learning_action(formation),
        potential_confidence_gain: estimate_confidence_gain_potential(formation)
      }
    end)
    |> Enum.filter(fn target -> target.learning_priority > 0.3 end)
    |> Enum.sort_by(& &1.learning_priority, :desc)
  end

  def track_belief_validation(topic, validation_outcome, validation_strength \\ 1.0) do
    case :ets.lookup(@belief_confidence_registry, topic) do
      [{^topic, formation}] ->
        validation_event = %{
          timestamp: DateTime.utc_now(),
          outcome: validation_outcome, # :confirmed, :contradicted, :partially_supported
          strength: validation_strength,
          confidence_before: formation.adjusted_confidence
        }
        
        calibration_data = formation.confidence_calibration_data
        updated_calibration = Map.update(calibration_data, :validation_events, 
          [validation_event], fn events -> [validation_event | events] end)
        
        updated_formation = formation
        |> Map.put(:confidence_calibration_data, updated_calibration)
        |> recalibrate_confidence_based_on_validation(validation_event)
        |> calculate_detailed_uncertainty_components()
        |> calculate_confidence_precision()
        |> update_confidence_trajectory()
        
        store_belief_confidence(topic, updated_formation)
        {:ok, updated_formation}
      
      [] ->
        {:error, :belief_not_found}
    end
  end

  def get_decision_making_confidence_profile do
    weighted_beliefs = get_confidence_weighted_beliefs()
    
    total_beliefs = length(weighted_beliefs)
    if total_beliefs == 0 do
      %{
        overall_confidence: 0.0,
        decision_reliability: :insufficient_data,
        high_confidence_ratio: 0.0,
        uncertainty_adjusted_confidence: 0.0,
        recommendation: "Insufficient belief data for confident decision-making"
      }
    else
      high_confidence_count = Enum.count(weighted_beliefs, fn b -> b.confidence >= 0.7 end)
      medium_confidence_count = Enum.count(weighted_beliefs, fn b -> b.confidence >= 0.4 and b.confidence < 0.7 end)
      
      avg_confidence = weighted_beliefs |> Enum.map(& &1.confidence) |> Enum.sum() |> Kernel./(total_beliefs)
      avg_uncertainty = weighted_beliefs |> Enum.map(& &1.uncertainty) |> Enum.sum() |> Kernel./(total_beliefs)
      
      uncertainty_adjusted_confidence = avg_confidence * (1 - avg_uncertainty * 0.5)
      
      %{
        total_beliefs: total_beliefs,
        overall_confidence: avg_confidence,
        uncertainty_adjusted_confidence: uncertainty_adjusted_confidence,
        high_confidence_ratio: high_confidence_count / total_beliefs,
        medium_confidence_ratio: medium_confidence_count / total_beliefs,
        average_uncertainty: avg_uncertainty,
        decision_reliability: classify_decision_reliability(uncertainty_adjusted_confidence, total_beliefs),
        confidence_distribution: %{
          high: high_confidence_count,
          medium: medium_confidence_count,
          low: total_beliefs - high_confidence_count - medium_confidence_count
        },
        recommendation: generate_decision_confidence_recommendation(uncertainty_adjusted_confidence, avg_uncertainty)
      }
    end
  end

  def revise_belief_with_evidence(topic, new_evidence, contradiction_level \\ nil) do
    case :ets.lookup(@belief_confidence_registry, topic) do
      [{^topic, formation}] ->
        contradiction_detected = contradiction_level && contradiction_level > @contradiction_threshold
        
        revised_formation = formation
        |> add_new_evidence(new_evidence)
        |> detect_contradictions(new_evidence, contradiction_level)
        |> maybe_trigger_revision(contradiction_detected)
        |> recalculate_confidence()
        |> update_revision_metrics()
        |> calculate_uncertainty_score()
        |> calculate_detailed_uncertainty_components()
        |> calculate_confidence_precision()
        |> assign_knowledge_quality_rating()
        |> update_confidence_trajectory()

        store_belief_confidence(topic, revised_formation)
        
        revision_outcome = determine_revision_outcome(formation, revised_formation)
        {:ok, revised_formation, revision_outcome}
      
      [] ->
        {:error, :belief_not_found}
    end
  end

  def get_revision_recommendations do
    start_confidence_tracking()
    
    :ets.tab2list(@belief_confidence_registry)
    |> Enum.map(fn {topic, formation} -> {topic, formation} end)
    |> Enum.filter(&should_consider_revision?/1)
    |> Enum.map(fn {topic, formation} ->
      %{
        topic: topic,
        current_confidence: formation.adjusted_confidence,
        revision_urgency: calculate_revision_urgency(formation),
        contradictions: length(formation.contradictions_detected),
        recommendation_type: get_revision_type(formation),
        last_revised: formation.last_revision_time
      }
    end)
    |> Enum.sort_by(& &1.revision_urgency, :desc)
  end

  def calculate_belief_confidence_score(topic) do
    case :ets.lookup(@belief_confidence_registry, topic) do
      [{^topic, formation}] ->
        confidence_components = %{
          base_confidence: formation.adjusted_confidence,
          evidence_strength: evidence_strength_score(formation),
          source_reliability: formation.uncertainty_factors.evidence_quality,
          temporal_stability: calculate_confidence_stability(formation),
          contradiction_impact: contradiction_penalty(formation),
          revision_stability: revision_stability_score(formation)
        }
        
        overall_score = calculate_weighted_confidence(confidence_components)
        
        {:ok, overall_score, confidence_components}
      
      [] ->
        {:error, :belief_not_found}
    end
  end

  def update_belief_confidence(belief_formation, new_evidence) do
    updated_evidence_count = belief_formation.evidence_count + length(new_evidence)
    
    updated_formation = belief_formation
    |> Map.put(:evidence_count, updated_evidence_count)
    |> Map.put(:evidence_sources, belief_formation.evidence_sources ++ new_evidence)
    |> calculate_uncertainty_factors(new_evidence)
    |> update_metacognitive_flags()
    |> adjust_confidence()
    |> calculate_uncertainty_score()
    |> calculate_detailed_uncertainty_components()
    |> calculate_confidence_precision()
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
        quality_distribution: %{},
        revision_summary: %{pending_revisions: 0, recently_revised: 0}
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
        problematic_beliefs: identify_problematic_beliefs(formations),
        revision_summary: calculate_revision_summary(formations)
      }
    end
  end

  def quantify_uncertainty_for_topic(topic) do
    case get_current_confidence(topic) do
      {:ok, confidence, uncertainty_score} ->
        uncertainty_breakdown = case :ets.lookup(@belief_confidence_registry, topic) do
          [{^topic, formation}] -> 
            formation.uncertainty_components || %{
              evidence_sufficiency: evidence_sufficiency_score(formation),
              source_reliability: formation.uncertainty_factors.evidence_quality,
              topic_complexity: topic_complexity_uncertainty(formation.topic),
              temporal_stability: formation.uncertainty_factors.temporal_consistency,
              conflict_level: formation.uncertainty_factors.conflicting_evidence,
              overall_uncertainty: uncertainty_score,
              confidence_stability: calculate_confidence_stability(formation),
              contradiction_impact: length(formation.contradictions_detected) * 0.1
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
        recommendation: generate_recommendation(formation),
        revision_needed: should_consider_revision?({topic, formation})
      }
    end)
  end

  # New confidence precision and uncertainty tracking functions

  defp calculate_detailed_uncertainty_components(formation) do
    components = %{
      evidence_sufficiency: evidence_sufficiency_score(formation),
      source_diversity: formation.uncertainty_factors.source_diversity || 0.5,
      temporal_consistency: formation.uncertainty_factors.temporal_consistency || 0.5,
      conflicting_evidence: formation.uncertainty_factors.conflicting_evidence || 0.0,
      topic_complexity: topic_complexity_uncertainty(formation.topic),
      validation_history: validation_history_uncertainty(formation),
      confidence_stability: calculate_confidence_stability(formation)
    }
    
    Map.put(formation, :uncertainty_components, components)
  end

  defp calculate_confidence_