defmodule LincolnWeb.PageControllerTest do
  use LincolnWeb.ConnCase

  test "GET / loads the dashboard", %{conn: conn} do
    conn = get(conn, ~p"/")
    assert html_response(conn, 200) =~ "LINCOLN"
    assert html_response(conn, 200) =~ "Neural Learning System"
  end

  test "GET /welcome loads the welcome page", %{conn: conn} do
    conn = get(conn, ~p"/welcome")
    assert html_response(conn, 200) =~ "Peace of mind from prototype to production"
  end
end
