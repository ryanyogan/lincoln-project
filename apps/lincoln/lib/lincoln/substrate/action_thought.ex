defmodule Lincoln.Substrate.ActionThought do
  @moduledoc """
  Substrate-native execution of pending tier-0/1 actions.

  When the `:action` impulse wins the Attention competition, the Thought
  delegates here. We pick the next executable action (highest predicted
  confidence first — fastest calibration signal), call the configured MCP
  tool through `Lincoln.Actions.execute/2`, and return a summary. Outcome
  observation, memory recording, and calibration belief formation are all
  handled inside `Lincoln.Actions` so the lifecycle stays in one place.
  """

  alias Lincoln.Actions
  alias Lincoln.Actions.Action

  require Logger

  def execute(agent) do
    case Actions.next_executable(agent) do
      nil ->
        {:ok, "No executable actions"}

      %Action{} = action ->
        run(action)
    end
  end

  defp run(action) do
    Logger.info(
      "[ActionThought] Executing #{action.tool_name} on #{action.tool_server} (tier #{action.risk_tier})"
    )

    case Actions.execute(action) do
      {:ok, %Action{status: "executed"} = updated} ->
        {:ok,
         "Executed #{updated.tool_name} (server #{updated.tool_server}) → #{summarize(updated.result)}"}

      {:ok, %Action{status: "failed"} = updated} ->
        {:ok, "Failed to execute #{updated.tool_name}: #{updated.error || "unknown"}"}

      {:error, reason} ->
        {:ok, "Action execution refused: #{inspect(reason)}"}
    end
  end

  defp summarize(nil), do: "no result"

  defp summarize(map) when is_map(map) do
    map
    |> inspect(limit: 4, printable_limit: 120)
    |> String.slice(0, 120)
  end
end
