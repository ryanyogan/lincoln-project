# Self-created by Lincoln for adaptive belief formation and
# metacognitive awareness. Implements confidence scoring and
# belief quality assessment.
#
# Self-modified: Enhanced with active belief confidence tracking
# and uncertainty quantification.
# Self-modified: Added belief revision mechanisms and enhanced
# confidence scoring.
# Self-modified: Enhanced confidence scoring precision and added
# belief uncertainty tracking.
# Self-modified: Completed confidence precision scoring and
# uncertainty component calculations.

defmodule Lincoln.Learning.BeliefFormation do
  @moduledoc """
  Implements adaptive confidence scoring and metacognitive awareness for belief formation.
  Tracks when beliefs are formed with insufficient evidence versus high confidence,
  and adjusts confidence based on topic complexity and uncertainty patterns.
  Enhanced with active tracking, real-time uncertainty quantification, and belief revision mechanisms.
  """

  # Note: @confidence_threshold reserved for future threshold-based filtering
  @evidence_minimum 3
  @revision_threshold 0.4
  @contradiction_threshold 0.6

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

    formation =
      %__MODULE__{
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
          # :confirmed, :contradicted, :partially_supported
          outcome: validation_outcome,
          strength: validation_strength,
          confidence_before: formation.adjusted_confidence
        }

        calibration_data = formation.confidence_calibration_data

        updated_calibration =
          Map.update(calibration_data, :validation_events, [validation_event], fn events ->
            [validation_event | events]
          end)

        updated_formation =
          formation
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

      medium_confidence_count =
        Enum.count(weighted_beliefs, fn b -> b.confidence >= 0.4 and b.confidence < 0.7 end)

      avg_confidence =
        weighted_beliefs |> Enum.map(& &1.confidence) |> Enum.sum() |> Kernel./(total_beliefs)

      avg_uncertainty =
        weighted_beliefs |> Enum.map(& &1.uncertainty) |> Enum.sum() |> Kernel./(total_beliefs)

      uncertainty_adjusted_confidence = avg_confidence * (1 - avg_uncertainty * 0.5)

      %{
        total_beliefs: total_beliefs,
        overall_confidence: avg_confidence,
        uncertainty_adjusted_confidence: uncertainty_adjusted_confidence,
        high_confidence_ratio: high_confidence_count / total_beliefs,
        medium_confidence_ratio: medium_confidence_count / total_beliefs,
        average_uncertainty: avg_uncertainty,
        decision_reliability:
          classify_decision_reliability(uncertainty_adjusted_confidence, total_beliefs),
        confidence_distribution: %{
          high: high_confidence_count,
          medium: medium_confidence_count,
          low: total_beliefs - high_confidence_count - medium_confidence_count
        },
        recommendation:
          generate_decision_confidence_recommendation(
            uncertainty_adjusted_confidence,
            avg_uncertainty
          )
      }
    end
  end

  def revise_belief_with_evidence(topic, new_evidence, contradiction_level \\ nil) do
    case :ets.lookup(@belief_confidence_registry, topic) do
      [{^topic, formation}] ->
        contradiction_detected =
          contradiction_level && contradiction_level > @contradiction_threshold

        revised_formation =
          formation
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

    updated_formation =
      belief_formation
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
      {:ok, _confidence, uncertainty_score} ->
        uncertainty_breakdown =
          case :ets.lookup(@belief_confidence_registry, topic) do
            [{^topic, formation}] ->
              formation.uncertainty_components ||
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

            [] ->
              %{}
          end

        {:ok, uncertainty_breakdown}

      error ->
        error
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

  defp calculate_confidence_precision(formation) do
    # Precision measures how reliable our confidence estimate is
    evidence_factor = min(formation.evidence_count / @evidence_minimum, 1.0)
    stability_factor = calculate_confidence_stability(formation)
    validation_factor = validation_history_uncertainty(formation)

    precision = evidence_factor * 0.4 + stability_factor * 0.3 + (1 - validation_factor) * 0.3
    Map.put(formation, :confidence_precision_score, precision)
  end

  defp validation_history_uncertainty(formation) do
    calibration = formation.confidence_calibration_data || %{}
    events = Map.get(calibration, :validation_events, [])

    if Enum.empty?(events) do
      # No validation history = moderate uncertainty
      0.5
    else
      contradicted = Enum.count(events, fn e -> e.outcome == :contradicted end)
      total = length(events)
      contradicted / total
    end
  end

  defp calculate_confidence_stability(formation) do
    trajectory = formation.confidence_trajectory || []

    if length(trajectory) < 2 do
      # Insufficient data for stability calculation
      0.5
    else
      confidences = Enum.map(trajectory, fn {_time, conf} -> conf end)
      variance = calculate_variance(confidences)
      # Convert variance to stability score
      max(0.0, 1.0 - variance * 2)
    end
  end

  defp calculate_variance(values) when length(values) < 2, do: 0.0

  defp calculate_variance(values) do
    mean = Enum.sum(values) / length(values)
    squared_diffs = Enum.map(values, fn v -> (v - mean) * (v - mean) end)
    Enum.sum(squared_diffs) / length(values)
  end

  defp topic_complexity_uncertainty(nil), do: 0.5

  defp topic_complexity_uncertainty(topic) when is_binary(topic) do
    # Estimate topic complexity based on characteristics
    word_count = topic |> String.split() |> length()
    technical_indicators = ["algorithm", "quantum", "neural", "distributed", "cryptographic"]
    has_technical = Enum.any?(technical_indicators, &String.contains?(String.downcase(topic), &1))

    base = 0.3
    base = if word_count > 3, do: base + 0.1, else: base
    base = if has_technical, do: base + 0.2, else: base
    min(base, 0.8)
  end

  defp topic_complexity_uncertainty(_), do: 0.5

  defp evidence_sufficiency_score(formation) do
    min(formation.evidence_count / (@evidence_minimum * 2), 1.0)
  end

  defp evidence_strength_score(formation) do
    # Combine evidence count and quality
    count_factor = min(formation.evidence_count / @evidence_minimum, 1.0)
    quality_factor = formation.uncertainty_factors.evidence_quality || 0.5
    count_factor * 0.5 + quality_factor * 0.5
  end

  defp contradiction_penalty(formation) do
    contradictions = formation.contradictions_detected || []
    penalty = length(contradictions) * 0.1
    min(penalty, 0.5)
  end

  defp revision_stability_score(formation) do
    # More revisions = less stable
    revisions = formation.revision_count || 0
    max(0.0, 1.0 - revisions * 0.1)
  end

  defp calculate_weighted_confidence(components) do
    weights = %{
      base_confidence: 0.3,
      evidence_strength: 0.2,
      source_reliability: 0.15,
      temporal_stability: 0.15,
      contradiction_impact: 0.1,
      revision_stability: 0.1
    }

    Enum.reduce(components, 0.0, fn {key, value}, acc ->
      weight = Map.get(weights, key, 0.0)
      adjusted_value = if key == :contradiction_impact, do: 1.0 - value, else: value
      acc + adjusted_value * weight
    end)
  end

  defp calculate_decision_weight(formation) do
    confidence = formation.adjusted_confidence || 0.5
    uncertainty = formation.uncertainty_score || 0.5
    precision = formation.confidence_precision_score || 0.5

    confidence * (1 - uncertainty * 0.5) * precision
  end

  defp classify_belief_reliability(formation) do
    weight = calculate_decision_weight(formation)

    cond do
      weight >= 0.7 -> :high
      weight >= 0.4 -> :medium
      true -> :low
    end
  end

  defp calculate_learning_priority(formation) do
    uncertainty = formation.uncertainty_score || 0.5
    evidence_gap = 1.0 - evidence_sufficiency_score(formation)
    flags_penalty = length(formation.metacognitive_flags || []) * 0.1

    uncertainty * 0.4 + evidence_gap * 0.4 + flags_penalty * 0.2
  end

  defp identify_primary_uncertainty_source(components) when map_size(components) == 0,
    do: :unknown

  defp identify_primary_uncertainty_source(components) do
    {source, _value} = Enum.max_by(components, fn {_k, v} -> v end)
    source
  end

  defp identify_evidence_gaps(formation) do
    gaps = []

    gaps =
      if formation.evidence_count < @evidence_minimum,
        do: [:insufficient_evidence | gaps],
        else: gaps

    gaps =
      if (formation.uncertainty_factors.source_diversity || 1.0) < 0.5,
        do: [:low_source_diversity | gaps],
        else: gaps

    gaps =
      if (formation.uncertainty_factors.conflicting_evidence || 0.0) > 0.3,
        do: [:conflicting_sources | gaps],
        else: gaps

    gaps
  end

  defp recommend_learning_action(formation) do
    cond do
      formation.evidence_count < @evidence_minimum -> :gather_more_evidence
      (formation.uncertainty_factors.source_diversity || 1.0) < 0.5 -> :diversify_sources
      (formation.uncertainty_factors.conflicting_evidence || 0.0) > 0.3 -> :resolve_conflicts
      formation.uncertainty_score > 0.6 -> :deepen_understanding
      true -> :maintain_observation
    end
  end

  defp estimate_confidence_gain_potential(formation) do
    current = formation.adjusted_confidence || 0.5
    gaps = identify_evidence_gaps(formation)
    gap_potential = length(gaps) * 0.15
    min(1.0 - current, gap_potential)
  end

  defp recalibrate_confidence_based_on_validation(formation, validation_event) do
    adjustment =
      case validation_event.outcome do
        :confirmed -> validation_event.strength * 0.05
        :contradicted -> -validation_event.strength * 0.1
        :partially_supported -> validation_event.strength * 0.02
        _ -> 0
      end

    new_confidence = max(0.0, min(1.0, formation.adjusted_confidence + adjustment))
    Map.put(formation, :adjusted_confidence, new_confidence)
  end

  defp update_confidence_trajectory(formation) do
    entry = {DateTime.utc_now(), formation.adjusted_confidence}
    trajectory = formation.confidence_trajectory || []
    # Keep last 20 entries
    updated = Enum.take([entry | trajectory], 20)
    Map.put(formation, :confidence_trajectory, updated)
  end

  defp classify_decision_reliability(confidence, belief_count) do
    cond do
      belief_count < 3 -> :insufficient_data
      confidence >= 0.7 -> :high
      confidence >= 0.5 -> :moderate
      confidence >= 0.3 -> :low
      true -> :very_low
    end
  end

  defp generate_decision_confidence_recommendation(confidence, uncertainty) do
    cond do
      confidence >= 0.7 and uncertainty < 0.3 ->
        "High confidence decision-making is supported"

      confidence >= 0.5 and uncertainty < 0.5 ->
        "Moderate confidence - proceed with awareness of limitations"

      uncertainty > 0.6 ->
        "High uncertainty - consider gathering more evidence before major decisions"

      true ->
        "Low confidence - exercise caution and verify critical assumptions"
    end
  end

  defp add_new_evidence(formation, new_evidence) do
    updated_sources = (formation.evidence_sources || []) ++ List.wrap(new_evidence)

    formation
    |> Map.put(:evidence_sources, updated_sources)
    |> Map.put(:evidence_count, length(updated_sources))
  end

  defp detect_contradictions(formation, new_evidence, contradiction_level) do
    if contradiction_level && contradiction_level > @contradiction_threshold do
      contradiction = %{
        evidence: new_evidence,
        level: contradiction_level,
        detected_at: DateTime.utc_now()
      }

      contradictions = [contradiction | formation.contradictions_detected || []]
      Map.put(formation, :contradictions_detected, contradictions)
    else
      formation
    end
  end

  defp maybe_trigger_revision(formation, true) do
    Map.put(formation, :revision_count, (formation.revision_count || 0) + 1)
  end

  defp maybe_trigger_revision(formation, false), do: formation

  defp recalculate_confidence(formation) do
    # Decrease confidence if contradictions detected
    contradiction_count = length(formation.contradictions_detected || [])
    penalty = min(contradiction_count * 0.1, 0.4)
    new_confidence = max(0.1, formation.adjusted_confidence - penalty)
    Map.put(formation, :adjusted_confidence, new_confidence)
  end

  defp update_revision_metrics(formation) do
    formation
    |> Map.put(:last_revision_time, DateTime.utc_now())
  end

  defp determine_revision_outcome(old_formation, new_formation) do
    confidence_change = new_formation.adjusted_confidence - old_formation.adjusted_confidence

    cond do
      confidence_change > 0.1 -> :strengthened
      confidence_change < -0.1 -> :weakened
      true -> :stable
    end
  end

  defp should_consider_revision?({_topic, formation}) do
    (formation.uncertainty_score || 0) > @revision_threshold or
      (formation.contradictions_detected || []) != [] or
      :high_uncertainty in (formation.metacognitive_flags || [])
  end

  defp calculate_revision_urgency(formation) do
    contradiction_factor = length(formation.contradictions_detected || []) * 0.2
    uncertainty_factor = formation.uncertainty_score || 0.5
    time_factor = calculate_staleness(formation)

    min(1.0, contradiction_factor + uncertainty_factor * 0.5 + time_factor * 0.3)
  end

  defp calculate_staleness(formation) do
    last_revision = formation.last_revision_time || DateTime.utc_now()
    days_since = DateTime.diff(DateTime.utc_now(), last_revision, :day)
    # Max staleness after 30 days
    min(days_since / 30, 1.0)
  end

  defp get_revision_type(formation) do
    contradiction_count = Enum.count(formation.contradictions_detected || [])

    cond do
      contradiction_count > 2 -> :major_revision
      (formation.uncertainty_score || 0) > 0.7 -> :evidence_gathering
      true -> :minor_update
    end
  end

  defp needs_attention?(formation, threshold) do
    (formation.uncertainty_score || 0) > threshold or
      (formation.contradictions_detected || []) != [] or
      calculate_revision_urgency(formation) > threshold
  end

  defp identify_issues(formation) do
    issues = []

    issues =
      if (formation.uncertainty_score || 0) > 0.6, do: [:high_uncertainty | issues], else: issues

    issues =
      if (formation.contradictions_detected || []) != [],
        do: [:has_contradictions | issues],
        else: issues

    issues =
      if formation.evidence_count < @evidence_minimum,
        do: [:insufficient_evidence | issues],
        else: issues

    issues
  end

  defp generate_recommendation(formation) do
    issues = identify_issues(formation)

    cond do
      :has_contradictions in issues -> "Resolve contradicting evidence"
      :high_uncertainty in issues -> "Gather more reliable sources"
      :insufficient_evidence in issues -> "Collect additional evidence"
      true -> "Monitor for changes"
    end
  end

  defp count_by_confidence(formations, min_conf, max_conf) do
    Enum.count(formations, fn f ->
      conf = f.adjusted_confidence || 0
      conf >= min_conf and conf < max_conf
    end)
  end

  defp calculate_average_uncertainty(formations) do
    if Enum.empty?(formations) do
      0.0
    else
      total = Enum.sum(Enum.map(formations, fn f -> f.uncertainty_score || 0 end))
      total / length(formations)
    end
  end

  defp calculate_quality_distribution(formations) do
    Enum.reduce(formations, %{excellent: 0, good: 0, fair: 0, poor: 0}, fn f, acc ->
      rating = f.knowledge_quality_rating || :fair
      Map.update(acc, rating, 1, &(&1 + 1))
    end)
  end

  defp identify_problematic_beliefs(formations) do
    formations
    |> Enum.filter(fn f ->
      (f.uncertainty_score || 0) > 0.7 or
        length(f.contradictions_detected || []) > 1
    end)
    |> Enum.map(fn f -> f.topic end)
  end

  defp calculate_revision_summary(formations) do
    recent_cutoff = DateTime.add(DateTime.utc_now(), -7, :day)

    recently_revised =
      Enum.count(formations, fn f ->
        f.last_revision_time && DateTime.compare(f.last_revision_time, recent_cutoff) == :gt
      end)

    pending =
      Enum.count(formations, fn f ->
        should_consider_revision?({f.topic, f})
      end)

    %{pending_revisions: pending, recently_revised: recently_revised}
  end

  # Core calculation functions from original implementation

  defp calculate_uncertainty_factors(formation, evidence_sources) do
    factors = %{
      evidence_quality: assess_evidence_quality(evidence_sources),
      source_diversity: assess_source_diversity(evidence_sources),
      # Default, would be calculated from historical data
      temporal_consistency: 0.7,
      conflicting_evidence: detect_conflicting_evidence(evidence_sources)
    }

    Map.put(formation, :uncertainty_factors, factors)
  end

  defp assess_evidence_quality(evidence_sources) do
    if Enum.empty?(evidence_sources) do
      0.3
    else
      # Simple heuristic - more sources = higher quality
      min(length(evidence_sources) * 0.2, 0.9)
    end
  end

  defp assess_source_diversity(evidence_sources) do
    if Enum.empty?(evidence_sources) do
      0.2
    else
      # Would ideally check for different source types
      min(length(evidence_sources) * 0.25, 1.0)
    end
  end

  defp detect_conflicting_evidence(_evidence_sources) do
    # Would analyze evidence for contradictions
    # Default low conflict
    0.1
  end

  defp apply_topic_complexity_adjustment(formation, topic) do
    complexity = topic_complexity_uncertainty(topic)
    adjusted = formation.base_confidence * (1 - complexity * 0.3)
    Map.put(formation, :adjusted_confidence, adjusted)
  end

  defp identify_metacognitive_flags(formation) do
    flags = []

    flags =
      maybe_add_flag(flags, :insufficient_evidence, formation.evidence_count < @evidence_minimum)

    flags = maybe_add_flag(flags, :high_uncertainty, (formation.uncertainty_score || 0.5) > 0.6)

    flags =
      maybe_add_flag(
        flags,
        :conflicting_sources,
        (formation.uncertainty_factors.conflicting_evidence || 0) > 0.3
      )

    flags = maybe_add_flag(flags, :novel_domain, novel_domain?(formation.topic))

    Map.put(formation, :metacognitive_flags, flags)
  end

  defp novel_domain?(nil), do: false

  defp novel_domain?(topic) when is_binary(topic) do
    novel_indicators = ["experimental", "cutting-edge", "emerging", "theoretical", "speculative"]
    Enum.any?(novel_indicators, &String.contains?(String.downcase(topic), &1))
  end

  defp novel_domain?(_), do: false

  defp adjust_confidence(formation) do
    base = formation.adjusted_confidence || formation.base_confidence
    flags = formation.metacognitive_flags || []

    penalty = Enum.reduce(flags, 0.0, fn flag, acc -> acc + flag_penalty(flag) end)
    adjusted = max(0.1, base - penalty)

    Map.put(formation, :adjusted_confidence, adjusted)
  end

  defp calculate_uncertainty_score(formation) do
    factors = formation.uncertainty_factors || %{}

    evidence_uncertainty = 1.0 - (factors.evidence_quality || 0.5)
    diversity_uncertainty = 1.0 - (factors.source_diversity || 0.5)
    conflict_score = factors.conflicting_evidence || 0.0

    score = evidence_uncertainty * 0.4 + diversity_uncertainty * 0.3 + conflict_score * 0.3
    Map.put(formation, :uncertainty_score, score)
  end

  defp assign_knowledge_quality_rating(formation) do
    confidence = formation.adjusted_confidence || 0.5
    uncertainty = formation.uncertainty_score || 0.5
    rating = quality_rating(confidence, uncertainty)
    Map.put(formation, :knowledge_quality_rating, rating)
  end

  defp quality_rating(conf, unc) when conf >= 0.8 and unc < 0.3, do: :excellent
  defp quality_rating(conf, unc) when conf >= 0.6 and unc < 0.5, do: :good
  defp quality_rating(conf, unc) when conf >= 0.4 and unc < 0.7, do: :fair
  defp quality_rating(_conf, _unc), do: :poor

  defp store_belief_confidence(topic, formation) do
    :ets.insert(@belief_confidence_registry, {topic, formation})
  end

  defp flag_penalty(flag) do
    case flag do
      :insufficient_evidence -> 0.2
      :high_uncertainty -> 0.15
      :conflicting_sources -> 0.1
      :novel_domain -> 0.05
      _ -> 0.0
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

    updated_history = [revision | formation.revision_history || []]
    Map.put(formation, :revision_history, updated_history)
  end

  # Public API for metacognitive queries
  def get_low_confidence_beliefs(min_threshold \\ 0.4) do
    start_confidence_tracking()

    :ets.tab2list(@belief_confidence_registry)
    |> Enum.filter(fn {_topic, formation} ->
      (formation.adjusted_confidence || 0) < min_threshold
    end)
    |> Enum.map(fn {topic, formation} ->
      %{
        topic: topic,
        confidence: formation.adjusted_confidence,
        issues: identify_issues(formation)
      }
    end)
  end

  def get_beliefs_with_insufficient_evidence do
    start_confidence_tracking()

    :ets.tab2list(@belief_confidence_registry)
    |> Enum.filter(fn {_topic, formation} ->
      :insufficient_evidence in (formation.metacognitive_flags || [])
    end)
    |> Enum.map(fn {topic, formation} ->
      %{topic: topic, evidence_count: formation.evidence_count, needed: @evidence_minimum}
    end)
  end

  def suggest_topics_for_deeper_exploration do
    get_uncertainty_prioritized_learning_targets()
    |> Enum.take(5)
  end

  def confidence_trend_analysis(topic) do
    case :ets.lookup(@belief_confidence_registry, topic) do
      [{^topic, formation}] ->
        analyze_trajectory(formation.confidence_trajectory || [])

      [] ->
        {:error, :topic_not_found}
    end
  end

  defp analyze_trajectory(trajectory) when length(trajectory) < 2 do
    {:ok, %{trend: :insufficient_data, data_points: length(trajectory)}}
  end

  defp analyze_trajectory(trajectory) do
    confidences = Enum.map(trajectory, fn {_time, conf} -> conf end)
    first = List.last(confidences)
    last = hd(confidences)
    change = last - first

    trend =
      cond do
        change > 0.1 -> :increasing
        change < -0.1 -> :decreasing
        true -> :stable
      end

    {:ok, %{trend: trend, change: change, data_points: length(trajectory)}}
  end
end
