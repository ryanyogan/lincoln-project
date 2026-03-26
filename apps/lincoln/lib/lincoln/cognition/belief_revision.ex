defmodule Lincoln.Cognition.BeliefRevision do
  @moduledoc """
  Confidence-based belief revision logic.

  Decides whether to revise beliefs based on:
  - Confidence levels (low confidence beliefs revise easily)
  - Entrenchment (core beliefs are protected)
  - Source hierarchy (observation > testimony > training)
  - Evidence strength (weak/moderate/strong)

  This implements a simplified version of AGM belief revision,
  adapted for practical use in a learning agent.

  ## Source Hierarchy

  The key insight for AGI research: Lincoln can override its training
  when observations contradict it. The hierarchy is:

  1. Observation (highest authority) - "I saw this happen"
  2. Testimony - "Someone told me this"
  3. Inference - "I derived this from other beliefs"
  4. Training (lowest authority) - "I was trained to believe this"

  This allows Lincoln to "wake up" and question pre-trained knowledge
  when lived experience contradicts it.
  """

  alias Lincoln.Beliefs
  alias Lincoln.Beliefs.Belief

  @type revision_decision ::
          {:revise, String.t()} | {:investigate, String.t()} | {:hold, String.t()}
  @type evidence_strength :: :weak | :moderate | :strong | nil

  @doc """
  Determines if a belief should be revised based on new evidence.

  ## Parameters
  - existing_belief: The belief being challenged
  - new_evidence: Map with :statement, :source_type, :strength

  ## Returns
  - {:revise, reason} - Update the belief
  - {:investigate, reason} - Notable but needs more evidence
  - {:hold, reason} - Keep existing belief
  """
  @spec should_revise?(Belief.t(), map()) :: revision_decision()
  def should_revise?(%Belief{} = existing_belief, new_evidence) do
    threshold = calculate_revision_threshold(existing_belief)
    evidence_score = calculate_evidence_score(new_evidence, existing_belief)

    cond do
      # Highly entrenched beliefs almost never revise
      existing_belief.entrenchment >= 8 and evidence_score < 0.9 ->
        {:hold, "Core belief protected by high entrenchment (#{existing_belief.entrenchment}/10)"}

      # Evidence clearly exceeds threshold
      evidence_score >= threshold * 1.2 ->
        {:revise,
         "Evidence score (#{Float.round(evidence_score, 2)}) exceeds threshold (#{Float.round(threshold, 2)})"}

      # Evidence is close to threshold - investigate
      evidence_score >= threshold * 0.7 ->
        {:investigate,
         "Evidence notable but not conclusive (#{Float.round(evidence_score, 2)} vs #{Float.round(threshold, 2)})"}

      # Evidence insufficient
      true ->
        {:hold,
         "Insufficient evidence for revision (#{Float.round(evidence_score, 2)} < #{Float.round(threshold, 2)})"}
    end
  end

  @doc """
  Calculates the threshold for revision based on belief properties.
  Higher threshold = harder to revise.
  """
  @spec calculate_revision_threshold(Belief.t()) :: float()
  def calculate_revision_threshold(%Belief{} = belief) do
    base = belief.confidence
    entrenchment_factor = belief.entrenchment / 10
    source_factor = source_weight(belief.source_type)

    # Base threshold is confidence * entrenchment * source weight
    # Higher confidence + higher entrenchment + trusted source = harder to revise
    base * (0.5 + entrenchment_factor * 0.5) * source_factor
  end

  @doc """
  Calculates the score of incoming evidence.
  Higher score = more compelling evidence.
  """
  @spec calculate_evidence_score(map(), Belief.t()) :: float()
  def calculate_evidence_score(evidence, existing_belief) do
    strength_score = strength_to_score(evidence[:strength])
    source_score = compare_sources(evidence[:source_type], existing_belief.source_type)

    # Evidence score is strength * source comparison
    # Strong evidence from trusted source = high score
    strength_score * source_score
  end

  @doc """
  Returns the weight of a source type.
  Higher weight = more trusted, harder to override.
  """
  @spec source_weight(atom() | String.t()) :: float()
  def source_weight(source_type) do
    case to_string(source_type) do
      "observation" -> 1.2
      "inference" -> 1.0
      "testimony" -> 0.8
      "training" -> 0.6
      _ -> 0.7
    end
  end

  @doc """
  Compares two source types and returns a multiplier.
  If new source outranks old source, multiplier is higher.
  """
  @spec compare_sources(atom() | String.t(), atom() | String.t()) :: float()
  def compare_sources(new_source, old_source) do
    new_weight = source_weight(new_source)
    old_weight = source_weight(old_source)

    # If new source is more trusted, boost evidence score
    # If old source is more trusted, reduce evidence score
    ratio = new_weight / old_weight

    # Clamp between 0.5 and 2.0
    min(max(ratio, 0.5), 2.0)
  end

  @doc """
  Executes a belief revision based on the decision.
  """
  @spec execute_revision(Belief.t(), map(), revision_decision()) ::
          {:ok, Belief.t()} | {:ok, :held} | {:ok, :investigating}
  def execute_revision(belief, evidence, decision) do
    case decision do
      {:revise, reason} ->
        # Create a new belief that supersedes the old one
        case Beliefs.supersede_belief(belief, evidence[:statement], reason) do
          {:ok, new_belief, _revision} -> {:ok, new_belief}
          {:error, reason} -> {:error, reason}
        end

      {:investigate, _reason} ->
        # Weaken the belief slightly to indicate uncertainty
        case Beliefs.weaken_belief(belief, "Contradicting evidence received, investigating") do
          {:ok, updated_belief, _revision} -> {:ok, :investigating, updated_belief}
          {:error, reason} -> {:error, reason}
        end

      {:hold, _reason} ->
        {:ok, :held}
    end
  end

  # ============================================================================
  # Private Functions
  # ============================================================================

  defp strength_to_score(:strong), do: 1.0
  defp strength_to_score(:moderate), do: 0.7
  defp strength_to_score(:weak), do: 0.4
  defp strength_to_score(nil), do: 0.5
  defp strength_to_score(_), do: 0.5
end
