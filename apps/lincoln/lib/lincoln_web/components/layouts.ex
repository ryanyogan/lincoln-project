defmodule LincolnWeb.Layouts do
  @moduledoc "Shared, quiet navigation for Lincoln and its workshop."
  use LincolnWeb, :html
  embed_templates("layouts/*")

  attr :flash, :map, required: true
  attr :current_scope, :map, default: nil
  attr :current_path, :string, default: "/"
  slot :inner_block, required: true

  def app(assigns) do
    ~H"""
    <div class="family-shell">
      <a href="#main-content" class="skip-link">Skip to content</a>
      <header class="family-header">
        <.link navigate={~p"/"} class="wordmark" aria-label="Lincoln home">
          lincoln<span>.</span>
        </.link>
        <nav aria-label="Main navigation" id="primary-navigation">
          <.link
            navigate={~p"/"}
            aria-current={
              if @current_path in ["/", "/chat"] or String.starts_with?(@current_path, "/chat/"),
                do: "page"
            }
          >
            Talk
          </.link>
          <.link navigate={~p"/journal"} aria-current={if @current_path == "/journal", do: "page"}>
            Family journal
          </.link>
          <.link navigate={~p"/goals"} aria-current={if @current_path == "/goals", do: "page"}>
            Commitments
          </.link>
        </nav>
        <details class="workshop-menu" id="workshop-menu">
          <summary>Workshop <.icon name="hero-chevron-down" class="size-3" /></summary>
          <nav aria-label="Workshop">
            <p>Under the surface</p>
            <.link navigate={~p"/workshop"}>Overview</.link>
            <.link navigate={~p"/substrate"}>Learning controls</.link>
            <.link navigate={~p"/beliefs"}>Understanding &amp; corrections</.link>
            <.link navigate={~p"/questions"}>Open questions</.link>
            <.link navigate={~p"/memories"}>All memories</.link>
            <.link navigate={~p"/actions"}>Action approvals</.link>
            <.link navigate={~p"/narrative"}>Lincoln’s reflections</.link>
            <.link navigate={~p"/substrate/compare"}>Compare experiments</.link>
            <.link navigate={~p"/substrate/thoughts"}>Running thoughts</.link>
            <.link navigate={~p"/benchmarks"}>Model checks</.link>
          </nav>
        </details>
      </header>
      <main id="main-content" class="family-main">{render_slot(@inner_block)}</main>
    </div>
    <.flash_group flash={@flash} />
    """
  end

  @doc """
  Shows the flash group with standard titles and content.
  """
  attr(:flash, :map, required: true, doc: "the map of flash messages")
  attr(:id, :string, default: "flash-group", doc: "the optional id of flash container")

  def flash_group(assigns) do
    ~H"""
    <div id={@id} aria-live="polite" class="toast toast-end toast-top z-50">
      <.flash kind={:info} flash={@flash} />
      <.flash kind={:error} flash={@flash} />

      <.flash
        id="client-error"
        kind={:error}
        title={gettext("CONNECTION LOST")}
        phx-disconnected={show(".phx-client-error #client-error") |> JS.remove_attribute("hidden")}
        phx-connected={hide("#client-error") |> JS.set_attribute({"hidden", ""})}
        hidden
      >
        <span class="flex items-center gap-2 font-terminal">
          {gettext("Attempting to reconnect")}
          <span class="loading loading-spinner loading-xs"></span>
        </span>
      </.flash>

      <.flash
        id="server-error"
        kind={:error}
        title={gettext("SYSTEM ERROR")}
        phx-disconnected={show(".phx-server-error #server-error") |> JS.remove_attribute("hidden")}
        phx-connected={hide("#server-error") |> JS.set_attribute({"hidden", ""})}
        hidden
      >
        <span class="flex items-center gap-2 font-terminal">
          {gettext("Attempting to reconnect")}
          <span class="loading loading-spinner loading-xs"></span>
        </span>
      </.flash>
    </div>
    """
  end
end
