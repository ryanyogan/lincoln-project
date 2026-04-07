defmodule Lincoln.Autonomy.SelfImprovement do
  @moduledoc """
  Lincoln's self-directed code improvement engine.

  Processes improvement opportunities from the queue:
  1. Analyze the struggle pattern
  2. Read relevant code
  3. Generate targeted improvement
  4. Apply and validate
  5. Commit with reasoning
  6. Schedule observation
  """

  require Logger

  alias Lincoln.Autonomy
  alias Lincoln.Autonomy.Evolution
  alias Lincoln.Events.{AdaptiveThresholds, Emitter, ImprovementQueue}
  alias Lincoln.Workers.ObservationWorker

  @doc """
  Process the next improvement opportunity in the queue.
  Returns :ok, :queue_empty, or :already_working
  """
  def process_next(agent, llm) do
    if ImprovementQueue.currently_working?(agent) do
      Logger.debug("Already working on an improvement for agent #{agent.id}")
      :already_working
    else
      case ImprovementQueue.next(agent) do
        nil ->
          Logger.debug("No pending improvements for agent #{agent.id}")
          :queue_empty

        opportunity ->
          attempt(agent, opportunity, llm)
      end
    end
  end

  @doc """
  Attempt to implement an improvement opportunity.
  """
  def attempt(agent, opportunity, llm) do
    Logger.info("Attempting improvement: #{opportunity.pattern} for agent #{agent.id}")

    {:ok, opportunity} = ImprovementQueue.mark_in_progress(opportunity)

    try do
      # 1. Analyze the struggle
      analysis = analyze_struggle(opportunity, llm)

      # 2. Read relevant code
      code_context = gather_code_context(analysis.target_files)

      # 3. Plan the improvement
      plan = plan_improvement(agent, opportunity, analysis, code_context, llm)

      if plan.should_proceed do
        execute_improvement(agent, opportunity, plan, llm)
      else
        Logger.info("Decided not to proceed with improvement: #{plan.reason}")
        ImprovementQueue.mark_completed(opportunity, "no_change")
        :skipped
      end
    rescue
      e ->
        Logger.error("Improvement attempt failed: #{inspect(e)}")
        ImprovementQueue.mark_failed(opportunity, inspect(e))
        {:error, e}
    end
  end

  # =============================================================================
  # Analysis Phase
  # =============================================================================

  defp analyze_struggle(opportunity, llm) do
    # For user-requested improvements, we already have the analysis from reflection
    if opportunity.pattern == "user_requested_improvement" do
      analyze_user_requested(opportunity)
    else
      analyze_detected_pattern(opportunity, llm)
    end
  end

  # User requested improvement already has description and reasoning from reflection
  defp analyze_user_requested(opportunity) do
    analysis = opportunity.analysis || %{}

    %{
      root_cause:
        analysis["description"] || analysis[:description] || "User requested improvement",
      target_files: [opportunity.suggested_focus] |> Enum.reject(&is_nil/1),
      change_type: "new_feature",
      confidence: 0.8
    }
  end

  # Pattern-detected struggles need LLM analysis
  defp analyze_detected_pattern(opportunity, llm) do
    prompt = """
    You are Lincoln, an AI agent analyzing your own struggles to improve yourself.

    A pattern has been detected that suggests you need to improve:

    Pattern: #{opportunity.pattern}
    Suggested Focus: #{opportunity.suggested_focus}
    Context: #{inspect(opportunity.analysis)}

    Based on this pattern, identify:
    1. The root cause of the struggle
    2. Which file(s) in your codebase are most likely responsible
    3. What kind of change would help

    Your codebase structure:
    - lib/lincoln/cognition/ - Cognitive processing (thought_loop, conversation_handler, perception)
    - lib/lincoln/learning/ - Learning systems (belief_formation)
    - lib/lincoln/autonomy/ - Autonomous behavior (evolution, self_improvement)
    - lib/lincoln/workers/ - Background workers (autonomous_learning_worker)
    - lib/lincoln/ - Core modules (beliefs, memory, questions)

    Return a JSON object with:
    {
      "root_cause": "Brief explanation of the likely cause",
      "target_files": ["lib/lincoln/path/to/file.ex"],
      "change_type": "documentation|refactor|logic|new_feature",
      "confidence": 0.0-1.0
    }
    """

    case llm.extract(prompt, %{type: "object"}, max_tokens: 500) do
      {:ok, analysis} ->
        %{
          root_cause: analysis["root_cause"] || "Unknown",
          target_files: analysis["target_files"] || [opportunity.suggested_focus],
          change_type: analysis["change_type"] || "refactor",
          confidence: analysis["confidence"] || 0.5
        }

      {:error, _} ->
        # Fallback to suggested focus
        %{
          root_cause: "Pattern detected: #{opportunity.pattern}",
          target_files: [opportunity.suggested_focus],
          change_type: "refactor",
          confidence: 0.3
        }
    end
  end

  defp gather_code_context(target_files) do
    target_files
    # Limit to 3 files for context
    |> Enum.take(3)
    |> Enum.map(fn path ->
      case Evolution.read_file(path) do
        {:ok, content} -> {path, content}
        {:error, _} -> nil
      end
    end)
    |> Enum.reject(&is_nil/1)
    |> Map.new()
  end

  # =============================================================================
  # Planning Phase
  # =============================================================================

  defp plan_improvement(_agent, opportunity, analysis, code_context, llm) do
    if analysis.confidence < 0.3 do
      %{should_proceed: false, reason: "Low confidence in analysis"}
    else
      target_file = List.first(analysis.target_files)

      if target_file && Map.has_key?(code_context, target_file) do
        current_code = code_context[target_file]

        prompt = """
        You are Lincoln, about to modify your own code to improve yourself.

        Pattern that triggered this: #{opportunity.pattern}
        Root cause analysis: #{analysis.root_cause}
        Target file: #{target_file}

        Current code:
        ```elixir
        #{String.slice(current_code, 0, 4000)}
        ```

        Should you proceed with a modification?
        Consider:
        - Is this change likely to help with the pattern?
        - Is it safe (won't break core functionality)?
        - Is it focused (minimal changes)?

        Return JSON:
        {
          "should_proceed": true/false,
          "reason": "Why or why not",
          "description": "What change you would make",
          "impact_scope": "minimal|moderate|significant|major"
        }
        """

        case llm.extract(prompt, %{type: "object"}, max_tokens: 400) do
          {:ok, plan} ->
            %{
              should_proceed: plan["should_proceed"] == true,
              reason: plan["reason"],
              description: plan["description"],
              impact_scope: String.to_atom(plan["impact_scope"] || "moderate"),
              target_file: target_file,
              change_type: analysis.change_type
            }

          {:error, _} ->
            %{should_proceed: false, reason: "Failed to generate plan"}
        end
      else
        %{should_proceed: false, reason: "Could not read target file"}
      end
    end
  end

  # =============================================================================
  # Execution Phase
  # =============================================================================

  defp execute_improvement(agent, opportunity, plan, llm) do
    Logger.info("Executing improvement: #{plan.description}")

    # Get or create a session for tracking
    session = Autonomy.get_active_session(agent) || create_improvement_session(agent)

    # Generate and apply the change
    with {:ok, code_change} <-
           Evolution.propose_change(
             agent,
             session,
             plan.target_file,
             plan.description,
             "Self-improvement triggered by pattern: #{opportunity.pattern}",
             llm
           ),
         {:ok, _applied} <- Evolution.apply_change(code_change),
         :ok <- validate_change(),
         {:ok, committed} <- Evolution.commit_change(code_change) do
      # Link the change to the opportunity
      ImprovementQueue.link_change(opportunity, committed)

      # Calculate observation period
      observation_seconds =
        AdaptiveThresholds.observation_period(
          plan.change_type,
          plan.impact_scope,
          agent
        )

      # Schedule observation
      schedule_observation(opportunity, committed, observation_seconds)

      # Emit success event
      Emitter.emit(agent, :code_change_applied, %{
        change_id: committed.id,
        opportunity_id: opportunity.id,
        file_path: committed.file_path,
        pattern: opportunity.pattern,
        observation_period: observation_seconds
      })

      Logger.info("Improvement applied successfully: #{committed.file_path}")
      {:ok, committed}
    else
      {:error, :compilation_failed, errors} ->
        Logger.error("Improvement failed compilation: #{errors}")
        ImprovementQueue.mark_failed(opportunity, "compilation_failed: #{errors}")
        {:error, :compilation_failed}

      {:error, reason} ->
        Logger.error("Improvement failed: #{inspect(reason)}")
        ImprovementQueue.mark_failed(opportunity, inspect(reason))
        {:error, reason}
    end
  end

  defp validate_change do
    case Evolution.validate_compilation() do
      :ok -> :ok
      {:error, reason} -> {:error, :compilation_failed, reason}
    end
  end

  defp create_improvement_session(agent) do
    case Autonomy.create_session(agent, %{trigger: "self_improvement"}) do
      {:ok, session} -> session
      {:error, _} -> nil
    end
  end

  defp schedule_observation(opportunity, code_change, seconds) do
    # Use Oban to schedule the observation
    %{
      opportunity_id: opportunity.id,
      code_change_id: code_change.id
    }
    |> ObservationWorker.new(schedule_in: seconds)
    |> Oban.insert()
  end
end
