defmodule LincolnWeb.JournalExportController do
  use LincolnWeb, :controller

  def show(conn, _params) do
    {:ok, agent} = Lincoln.Agents.get_or_create_default_agent()
    payload = agent |> Lincoln.FamilyJournal.export() |> Jason.encode!(pretty: true)

    conn
    |> put_resp_content_type("application/json")
    |> put_resp_header("cache-control", "no-store")
    |> put_resp_header(
      "content-disposition",
      ~s(attachment; filename="lincoln-family-journal.json")
    )
    |> send_resp(200, payload)
  end
end
