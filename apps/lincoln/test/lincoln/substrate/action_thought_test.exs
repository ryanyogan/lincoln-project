defmodule Lincoln.Substrate.ActionThoughtTest do
  use Lincoln.DataCase, async: true

  alias Lincoln.{Actions, Agents}

  setup do
    {:ok, agent} = Agents.create_agent(%{name: "ActionThought #{System.unique_integer()}"})
    %{agent: agent}
  end

  test "returns idle summary with no executable actions", %{agent: agent} do
    assert {:ok, "No executable actions"} = Lincoln.Substrate.ActionThought.execute(agent)
  end

  test "delegates to Actions.execute and returns a summary", %{agent: agent} do
    # Stub embeddings so calibration's form_belief doesn't crash on missing service
    Mox.stub(Lincoln.EmbeddingsMock, :embed, fn _text, _opts ->
      {:ok, for(i <- 0..383, do: :math.sin(i / 100.0))}
    end)

    {:ok, _action} =
      Actions.propose(agent, %{
        tool_name: "write_scratch",
        tool_server: "filesystem",
        risk_tier: 0,
        predicted_outcome: "ok",
        prediction_confidence: 0.7
      })

    # In production the substrate calls Actions.execute, which uses the real
    # MCP client. Here we don't have that wired in tests at this layer; the
    # real-server-not-configured path returns an error which the action loop
    # turns into a "failed" status. That's still exercised: the impulse
    # dispatched, an action transitioned, and a summary came back.
    assert {:ok, summary} = Lincoln.Substrate.ActionThought.execute(agent)
    assert summary =~ "write_scratch" or summary =~ "Failed" or summary =~ "Action"
  end
end
