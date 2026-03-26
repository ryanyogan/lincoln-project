# Self-created by Lincoln for adaptive belief formation and metacognitive awareness
# This module implements confidence scoring and belief quality assessment
# Self-modified: Enhanced with active belief confidence tracking and uncertainty quantification for improved metacognitive reasoning
# Self-modified: Added comprehensive belief revision mechanisms and enhanced confidence scoring for better knowledge management

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
    :evidence_sources
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
      evidence_sources: evidence_sources
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
            %{
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

  # Belief revision mechanism helpers
  defp add_new_evidence(formation, new_evidence) do
    updated_sources = formation.evidence_sources ++ new_evidence
    updated_count = length(updated_sources)
    
    formation
    |> Map.put(:evidence_sources, updated_sources)
    |> Map.put(:evidence_count, updated_count)
  end

  defp detect_contradictions(formation, new_evidence, contradiction_level) do
    new_contradictions = if contradiction_level && contradiction_level > @contradiction_threshold do
      contradiction_entry = %{
        detected_at: DateTime.utc_now(),
        contradiction_level: contradiction_level,
        conflicting_evidence: new_evidence,
        resolution_status: :unresolved
      }
      [contradiction_entry | formation.contradictions_detected]
    else
      formation.contradictions_detected
    end
    
    Map.put(formation, :contradictions_detected, new_contradictions)
  end

  defp maybe_trigger_revision(formation, should_revise) do
    if should_revise || formation.adjusted_confidence < @revision_threshold do
      trigger_belief_revision(formation)
    else
      formation
    end
  end

  defp trigger_belief_revision(formation) do
    revision_entry = %{
      timestamp: DateTime.utc_now(),
      previous_confidence: formation.adjusted_confidence,
      reason: determine_revision_reason(formation),
      evidence_at_revision: formation.evidence_count
    }
    
    formation
    |> Map.put(:revision_history, [revision_entry | formation.revision_history])
    |> Map.put(:last_revision_time, DateTime.utc_now())
    |> Map.put(:revision_count, formation.revision_count + 1)
  end

  defp recalculate_confidence(formation) do
    formation
    |> calculate_uncertainty_factors(formation.evidence_sources)
    |> apply_topic_complexity_adjustment(formation.topic)
    |> identify_metacognitive_flags()
    |> adjust_confidence()
  end

  defp update_revision_metrics(formation) do
    # Additional metrics tracking could be added here
    formation
  end

  defp determine_revision_outcome(old_formation, new_formation) do
    confidence_change = new_formation.adjusted_confidence - old_formation.adjusted_confidence
    
    cond do
      confidence_change > 0.2 -> :confidence_increased
      confidence_change < -0.2 -> :confidence_decreased
      length(new_formation.contradictions_detected) > length(old_formation.contradictions_detected) -> :contradiction_detected
      new_formation.evidence_count > old_formation.evidence_count -> :evidence_added
      true -> :minor_update
    end
  end

  defp should_consider_revision?({_topic, formation}) do
    days_since_revision = DateTime.diff(DateTime.utc_now(), formation.last_revision_time, :day)
    
    formation.adjusted_confidence < @revision_threshold ||
    length(formation.contradictions_detected) > 0 ||
    formation.uncertainty_score > 0.7 ||
    (days_since_revision > 30 && formation.adjusted_confidence < 0.6)
  end

  defp calculate_revision_urgency(formation) do
    urgency_factors = [
      confidence_urgency(formation.adjusted_confidence),
      contradiction_urgency(formation.contradictions_detected),
      temporal_urgency(formation.last_revision_time),
      uncertainty_urgency(formation.uncertainty_score)
    ]
    
    Enum.sum(urgency_factors) / length(urgency_factors)
  end

  defp confidence_urgency(confidence) when confidence < 0.3, do: 1.0
  defp confidence_urgency(confidence) when confidence < 0.5, do: 0.7
  defp confidence_urgency(_), do: 0.2

  defp contradiction_urgency(contradictions) do
    unresolved = Enum.count(contradictions, fn c -> c.resolution_status == :unresolved end)
    min(unresolved * 0.3, 1.0)
  end

  defp temporal_urgency(last_revision) do
    days_ago = DateTime.diff(DateTime.utc_now(), last_revision, :day)
    cond do
      days_ago > 90 -> 0.8
      days_ago > 60 -> 0.5
      days_ago > 30 -> 0.3
      true -> 0.1
    end
  end

  defp uncertainty_urgency(uncertainty) when uncertainty > 0.8, do: 1.0
  defp uncertainty_urgency(uncertainty) when uncertainty > 0.6, do: 0.6
  defp uncertainty_urgency(_), do: 0.2

  defp get_revision_type(formation) do
    cond do
      formation.adjusted_confidence < 0.3 -> :confidence_restoration
      length(formation.contradictions_detected) > 0 -> :contradiction_resolution
      formation.evidence_count < @evidence_minimum -> :evidence_gathering
      formation.uncertainty_score > 0.7 -> :uncertainty_reduction
      true -> :routine_review
    end
  end

  defp determine_revision_reason(formation) do
    cond do
      formation.adjusted_confidence < @revision_threshold -> :low_confidence
      length(formation.contradictions_detected) > 0 -> :contradictions_detected
      formation.uncertainty_score > 0.7 -> :high_uncertainty
      true -> :routine_maintenance
    end
  end

  defp evidence_strength_score(formation) do
    base_score = min(formation.evidence_count / 5.0, 1.0)
    quality_bonus = formation.uncertainty_factors.evidence_quality * 0.3
    diversity_bonus = formation.uncertainty_factors.source_diversity * 0.2
    
    min(base_score + quality_bonus + diversity_bonus, 1.0)
  end

  defp contradiction_penalty(formation) do
    unresolved_count = Enum.count(formation.contradictions_detected, fn c -> 
      c.resolution_status == :unresolved 
    end)
    
    unresolved_count * 0.