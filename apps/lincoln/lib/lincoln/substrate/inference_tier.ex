defmodule Lincoln.Substrate.InferenceTier do
  @moduledoc """
  Selects the appropriate inference tier based on attention score and budget.

  Three tiers:
  - :local (Level 0) — pure computation, no model call
  - :ollama (Level 1) — local model via Ollama, cheap
  - :claude (Level 2) — frontier model, expensive, high-attention only
  """

  # Thresholds (configurable via opts)
  @ollama_threshold 0.3
  @claude_threshold 0.7

  @doc """
  Select inference tier based on attention score.

  Options:
  - :budget — budget tier atom (:full, :moderate, :conservative, :minimal)
              When :minimal, forces :local regardless of score
  - :ollama_threshold — override default 0.3 threshold
  - :claude_threshold — override default 0.7 threshold

  Returns one of: :local, :ollama, :claude
  """
  def select_tier(attention_score, opts \\ [])
      when (is_float(attention_score) or is_integer(attention_score)) and is_list(opts) do
    budget = Keyword.get(opts, :budget, :full)

    # Budget override — when minimal, always local
    if budget == :minimal do
      :local
    else
      ollama_threshold = Keyword.get(opts, :ollama_threshold, @ollama_threshold)
      claude_threshold = Keyword.get(opts, :claude_threshold, @claude_threshold)

      cond do
        attention_score >= claude_threshold -> :claude
        attention_score >= ollama_threshold -> :ollama
        true -> :local
      end
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
        # Fall back to claude
        execute_at_tier(:claude, messages, opts)

      {:error, reason} ->
        {:error, reason}
    end
  end

  def execute_at_tier(:claude, messages, opts) do
    llm = Application.get_env(:lincoln, :llm_adapter, Lincoln.Adapters.LLM.Anthropic)
    llm.chat(messages, opts)
  end
end
