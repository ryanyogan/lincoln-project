defmodule LincolnWeb.GoalsLiveTest do
  @moduledoc """
  Smoke tests for the Goals LiveView. Verifies render, creation, and status
  transitions wire through the Goals context cleanly. Detailed Goals
  context behaviour is covered in `Lincoln.GoalsTest`.
  """

  use LincolnWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias Lincoln.{Agents, Goals}

  setup do
    # The LiveView uses get_or_create_default_agent — make sure one exists.
    {:ok, agent} = Agents.get_or_create_default_agent()
    %{agent: agent}
  end

  test "renders the goals page", %{conn: conn} do
    {:ok, _view, html} = live(conn, ~p"/goals")
    assert html =~ "Goals"
    assert html =~ "New goal"
  end

  test "creating a goal via the form streams it onto the page", %{conn: conn, agent: agent} do
    {:ok, view, _html} = live(conn, ~p"/goals")

    view
    |> form("#goal-form",
      goal: %{statement: "Take the kids to the park", priority: 7}
    )
    |> render_submit()

    rendered = render(view)
    assert rendered =~ "Take the kids to the park"
    assert rendered =~ "priority 7/10"

    [goal] = Goals.list_goals(agent, status: "active") |> Enum.filter(&(&1.statement =~ "park"))
    assert goal.priority == 7
  end

  test "filters goals by status", %{conn: conn, agent: agent} do
    {:ok, _} = Goals.create_goal(agent, %{statement: "Ongoing thing"})

    {:ok, achieved} = Goals.create_goal(agent, %{statement: "Done thing"})
    {:ok, _} = Goals.update_status(achieved, "achieved")

    {:ok, view, _} = live(conn, ~p"/goals")
    initial = render(view)
    assert initial =~ "Ongoing thing"
    refute initial =~ "Done thing"

    after_filter = render_click(view, "filter", %{"status" => "achieved"})
    assert after_filter =~ "Done thing"
    refute after_filter =~ "Ongoing thing"
  end
end
