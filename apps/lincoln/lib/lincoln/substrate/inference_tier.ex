defmodule Lincoln.Substrate.InferenceTier do
  @moduledoc """
  Selects the appropriate inference tier based on attention score, budget,
  and belief coverage.

  Three tiers:
  - :local (Level 0) — reason from belief graph, no model call
  - :ollama (Level 1) — local model via Ollama, cheap
  - :claude (Level 2) — frontier model, expensive, only for genuine gaps

  Over time, as the belief graph grows, more thoughts should resolve
  locally. The LLM is called only when beliefs are insufficient.
  """

  alias Lincoln.Beliefs

  # Thresholds (configurable via opts)
  @ollama_threshold 0.3
  @claude_threshold 0.7

  @doc """
  Select inference tier based on attention score and belief coverage.

  Options:
  - :budget — budget tier atom (:full, :moderate, :conservative, :minimal)
  - :belief — the belief being thought about (for coverage check)
  - :agent — the agent (for belief graph queries)
  - :ollama_threshold — override default 0.3
  - :claude_threshold — override default 0.7

  Returns one of: :local, :ollama, :claude
  """
  def select_tier(attention_score, opts \\ [])
      when (is_float(attention_score) or is_integer(attention_score)) and is_list(opts) do
    budget = Keyword.get(opts, :budget, :full)

    cond do
      budget == :minimal ->
        :local

      belief_well_covered?(opts) ->
        :local

      attention_score >= Keyword.get(opts, :claude_threshold, @claude_threshold) ->
        :claude

      attention_score >= Keyword.get(opts, :ollama_threshold, @ollama_threshold) ->
        :ollama

      true ->
        :local
    end
  end

  @doc """
  Execute action at appropriate tier.

  Returns:
  - {:ok, :skipped} — for :local tier (no model call)
  - {:ok, response} — for :ollama or :claude tiers
  - {:error, reason} — on failure

  Falls back: :ollama failure → :claude; :claude failure → error
  """
  def execute_at_tier(:local, _messages, _opts) do
    {:ok, :skipped}
  end

  def execute_at_tier(:ollama, messages, opts) do
    ollama = Application.get_env(:lincoln, :ollama_adapter, Lincoln.Adapters.LLM.Ollama)

    case ollama.chat(messages, opts) do
      {:ok, response} ->
        {:ok, response}

      {:error, :ollama_unavailable} ->
        execute_at_tier(:claude, messages, opts)

      {:error, reason} ->
        {:error, reason}
    end
  end

  def execute_at_tier(:claude, messages, opts) do
    llm = Application.get_env(:lincoln, :llm_adapter, Lincoln.Adapters.LLM.Anthropic)
    llm.chat(messages, opts)
  end

  # A belief is "well covered" if the graph already has enough information
  # about it that an LLM call would add diminishing returns.
  defp belief_well_covered?(opts) do
    agent = Keyword.get(opts, :agent)
    belief = Keyword.get(opts, :belief)

    if agent && belief && is_binary(belief.id) do
      relationships = Beliefs.find_relationships(agent, belief.id)
      support_count = Enum.count(relationships, &(&1.relationship_type == "supports"))
      derived_count = Enum.count(relationships, &(&1.relationship_type == "derived_from"))

      # Well-covered ONLY if the belief graph shows genuine connections:
      # - 3+ support relationships, OR
      # - 2+ derived_from relationships (belief has produced offspring)
      # Revision count is NOT a signal — local entrenchment inflates it
      support_count >= 3 or derived_count >= 2
    else
      false
    end
  rescue
    _ -> false
  end
end
