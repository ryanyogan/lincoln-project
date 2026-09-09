defmodule LincolnWeb.PageControllerTest do
  use LincolnWeb.ConnCase

  test "GET / loads the conversation workspace", %{conn: conn} do
    conn = get(conn, ~p"/")
    assert html_response(conn, 200) =~ "Lincoln"
    document = conn |> html_response(200) |> LazyHTML.from_fragment()
    assert document |> LazyHTML.query("#chat-form") |> Enum.count() == 1
  end

  test "GET /welcome loads the welcome page", %{conn: conn} do
    conn = get(conn, ~p"/welcome")
    assert html_response(conn, 200) =~ "Peace of mind from prototype to production"
  end
end
