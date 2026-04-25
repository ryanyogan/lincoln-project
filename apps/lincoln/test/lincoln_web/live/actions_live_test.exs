defmodule LincolnWeb.ActionsLiveTest do
  use LincolnWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias Lincoln.{Actions, Agents}

  setup do
    {:ok, agent} = Agents.get_or_create_default_agent()
    %{agent: agent}
  end

  test "renders pending tier-2 actions and approves them", %{conn: conn, agent: agent} do
    {:ok, action} =
      Actions.propose(agent, %{
        tool_name: "send_email",
        tool_server: "gmail",
        risk_tier: 2,
        predicted_outcome: "user replies same day",
        prediction_confidence: 0.4,
        arguments: %{}
      })

    {:ok, view, html} = live(conn, ~p"/actions")
    assert html =~ "send_email"
    assert html =~ "tier 2"

    render_click(view, "approve", %{"id" => action.id})

    reloaded = Actions.get_action!(action.id)
    assert reloaded.status == "proposed"
  end

  test "filter switching re-streams the list", %{conn: conn, agent: agent} do
    {:ok, _pending} =
      Actions.propose(agent, %{tool_name: "tool_pending", tool_server: "y", risk_tier: 2})

    {:ok, _executable} =
      Actions.propose(agent, %{tool_name: "tool_proposed", tool_server: "y", risk_tier: 0})

    {:ok, view, _} = live(conn, ~p"/actions")
    initial = render(view)
    assert initial =~ "tool_pending"
    refute initial =~ "tool_proposed"

    after_filter = render_click(view, "filter", %{"status" => "proposed"})
    assert after_filter =~ "tool_proposed"
    refute after_filter =~ "tool_pending"
  end
end
