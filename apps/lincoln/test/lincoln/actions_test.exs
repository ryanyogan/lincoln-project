defmodule Lincoln.ActionsTest do
  use Lincoln.DataCase, async: true

  import Mox

  alias Lincoln.{Actions, Agents, Beliefs, Memory}
  alias Lincoln.Actions.Action

  setup :verify_on_exit!

  setup do
    {:ok, agent} = Agents.create_agent(%{name: "Actions Test #{System.unique_integer()}"})
    %{agent: agent}
  end

  describe "propose/2" do
    test "creates a tier-0 action in the proposed status", %{agent: agent} do
      assert {:ok, %Action{} = action} =
               Actions.propose(agent, %{
                 tool_name: "write_scratch_note",
                 tool_server: "filesystem",
                 risk_tier: 0,
                 predicted_outcome: "note saved",
                 prediction_confidence: 0.8
               })

      assert action.status == "proposed"
      assert action.risk_tier == 0
    end

    test "tier-2 actions are parked at pending_approval", %{agent: agent} do
      assert {:ok, %Action{status: "pending_approval"}} =
               Actions.propose(agent, %{
                 tool_name: "send_email",
                 tool_server: "gmail",
                 risk_tier: 2
               })
    end

    test "validates required fields", %{agent: agent} do
      assert {:error, changeset} = Actions.propose(agent, %{tool_name: ""})
      errors = errors_on(changeset)
      assert errors[:tool_name] != nil
      assert errors[:tool_server] != nil
    end
  end

  describe "executable?/1" do
    test "is true for proposed tier 0/1, false otherwise" do
      assert Actions.executable?(%Action{status: "proposed", risk_tier: 0})
      assert Actions.executable?(%Action{status: "proposed", risk_tier: 1})
      refute Actions.executable?(%Action{status: "proposed", risk_tier: 2})
      refute Actions.executable?(%Action{status: "pending_approval", risk_tier: 1})
      refute Actions.executable?(%Action{status: "executed", risk_tier: 0})
    end
  end

  describe "count_executable / next_executable" do
    test "counts only autonomous-tier proposed actions", %{agent: agent} do
      {:ok, _t0} = Actions.propose(agent, fixture(tool_name: "a", risk_tier: 0))
      {:ok, _t1} = Actions.propose(agent, fixture(tool_name: "b", risk_tier: 1))
      {:ok, _t2} = Actions.propose(agent, fixture(tool_name: "c", risk_tier: 2))

      assert Actions.count_executable(agent) == 2
    end

    test "next_executable returns highest-confidence proposed action", %{agent: agent} do
      {:ok, low} =
        Actions.propose(
          agent,
          fixture(tool_name: "low", risk_tier: 0, prediction_confidence: 0.3)
        )

      {:ok, high} =
        Actions.propose(
          agent,
          fixture(tool_name: "high", risk_tier: 0, prediction_confidence: 0.9)
        )

      assert %Action{id: id} = Actions.next_executable(agent)
      assert id == high.id
      refute id == low.id
    end
  end

  describe "execute/2 — success path" do
    test "calls the MCP tool, persists outcome, writes observation memory + calibration belief",
         %{agent: agent} do
      stub(Lincoln.EmbeddingsMock, :embed, fn _text, _opts -> {:ok, fake_embedding(0.5)} end)

      {:ok, action} =
        Actions.propose(
          agent,
          fixture(
            tool_name: "write_scratch_note",
            tool_server: "filesystem",
            risk_tier: 0,
            predicted_outcome: "note written",
            prediction_confidence: 0.8
          )
        )

      mcp = MockMCP.expect_success(%{"path" => "/tmp/note.txt"})

      assert {:ok, %Action{} = updated} = Actions.execute(action, mcp_client: mcp)
      assert updated.status == "executed"
      assert updated.result["path"] == "/tmp/note.txt"
      assert updated.executed_at
      assert updated.observation_memory_id

      [memory] = Memory.list_memories_by_type(agent, "observation")
      assert memory.content =~ "Executed write_scratch_note"
      assert memory.content =~ "Outcome: success"
      assert memory.source_context["action_id"] == action.id

      [belief] = Beliefs.list_beliefs(agent, status: "active")
      assert belief.statement =~ "write_scratch_note"
      assert belief.source_type == "observation"
    end
  end

  describe "execute/2 — failure path" do
    test "records failure, writes observation memory, calibrates downward", %{agent: agent} do
      stub(Lincoln.EmbeddingsMock, :embed, fn _text, _opts -> {:ok, fake_embedding(0.5)} end)

      {:ok, action} =
        Actions.propose(
          agent,
          fixture(
            tool_name: "send_message",
            tool_server: "slack",
            risk_tier: 1,
            predicted_outcome: "delivered",
            prediction_confidence: 0.9
          )
        )

      mcp = MockMCP.expect_failure(:rate_limited)

      assert {:ok, %Action{status: "failed"} = updated} =
               Actions.execute(action, mcp_client: mcp)

      assert updated.error =~ "rate_limited"

      [memory] = Memory.list_memories_by_type(agent, "observation")
      assert memory.content =~ "Outcome: failure"

      [belief] = Beliefs.list_beliefs(agent, status: "active")
      assert belief.statement =~ "sometimes fails"
    end
  end

  describe "execute/2 — refuses non-executable actions" do
    test "tier-2 actions are not auto-executed", %{agent: agent} do
      {:ok, action} =
        Actions.propose(agent, fixture(tool_name: "x", tool_server: "y", risk_tier: 2))

      mcp = MockMCP.expect_unused()

      assert {:error, {:not_executable, "pending_approval", 2}} =
               Actions.execute(action, mcp_client: mcp)
    end
  end

  describe "approve/1" do
    test "moves a pending_approval action to proposed", %{agent: agent} do
      {:ok, action} =
        Actions.propose(agent, fixture(tool_name: "x", tool_server: "y", risk_tier: 2))

      assert {:ok, approved} = Actions.approve(action)
      assert approved.status == "proposed"
    end
  end

  defp fixture(overrides) do
    Map.merge(
      %{
        tool_name: "noop",
        tool_server: "filesystem",
        arguments: %{},
        risk_tier: 0,
        reversibility: "reversible",
        predicted_outcome: "ok",
        prediction_confidence: 0.5
      },
      Map.new(overrides)
    )
  end

  defp fake_embedding(seed) do
    for i <- 0..383, do: :math.sin(seed + i / 100.0)
  end
end
