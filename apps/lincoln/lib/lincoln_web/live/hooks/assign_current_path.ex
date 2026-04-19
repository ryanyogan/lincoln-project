defmodule LincolnWeb.Live.Hooks.AssignCurrentPath do
  @moduledoc """
  on_mount hook that tracks the current path for active nav highlighting.
  Attaches to handle_params so it updates on every live navigation.
  """
  import Phoenix.LiveView
  import Phoenix.Component, only: [assign: 3]

  def on_mount(:default, _params, _session, socket) do
    {:cont,
     attach_hook(socket, :current_path, :handle_params, fn _params, uri, socket ->
       {:cont, assign(socket, :current_path, URI.parse(uri).path)}
     end)}
  end
end
