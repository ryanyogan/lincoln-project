defmodule LincolnWeb.PageController do
  use LincolnWeb, :controller

  def home(conn, _params) do
    render(conn, :home)
  end
end
