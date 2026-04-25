defmodule LincolnWeb.Layouts do
  @moduledoc """
  Lincoln Neural Dashboard — West World Neobrutalism layout.

  Drawer + navbar with neobrutalist styling: thick borders, offset shadows,
  terminal fonts, active nav tracking via @current_path.
  """
  use LincolnWeb, :html

  embed_templates("layouts/*")

  @doc """
  Renders the app layout with neobrutalist drawer navigation.
  """
  attr(:flash, :map, required: true, doc: "the map of flash messages")

  attr(:current_scope, :map,
    default: nil,
    doc: "the current [scope](https://hexdocs.pm/phoenix/scopes.html)"
  )

  slot(:inner_block, required: true)

  def app(assigns) do
    ~H"""
    <div class="drawer lg:drawer-open">
      <input id="lincoln-drawer" type="checkbox" class="drawer-toggle" />

      <%!-- Main content area --%>
      <div class="drawer-content flex flex-col min-h-screen bg-base-100">
        <%!-- Navbar — thick bottom border, neobrutalist --%>
        <div class="navbar bg-base-200 border-b-2 border-base-300 sticky top-0 z-30">
          <div class="navbar-start">
            <label
              for="lincoln-drawer"
              class="btn btn-ghost btn-square lg:hidden"
              aria-label="Open menu"
            >
              <.icon name="hero-bars-3" class="size-5" />
            </label>
            <.link
              navigate={~p"/"}
              class="btn btn-ghost gap-2 text-xl font-terminal font-bold uppercase tracking-tight"
            >
              <div class="relative">
                <.icon name="hero-cpu-chip" class="size-6 text-primary" />
                <span class="absolute -bottom-0.5 -right-0.5 status-dot status-dot-online"></span>
              </div>
              <span class="hidden sm:inline">Lincoln</span>
            </.link>
          </div>

          <div class="navbar-center hidden lg:flex">
            <ul class="menu menu-horizontal gap-1">
              <li>
                <.link navigate={~p"/"} class={["text-sm font-terminal", nav_active?(assigns, "/")]}>
                  <.icon name="hero-squares-2x2" class="size-4" /> Dashboard
                </.link>
              </li>
              <li>
                <.link
                  navigate={~p"/chat"}
                  class={["text-sm font-terminal", nav_active?(assigns, "/chat")]}
                >
                  <.icon name="hero-chat-bubble-left-right" class="size-4" /> Chat
                </.link>
              </li>
              <li>
                <details>
                  <summary class={["text-sm font-terminal", nav_group_active?(assigns, "/substrate")]}>
                    <.icon name="hero-cpu-chip" class="size-4" /> Substrate
                  </summary>
                  <ul class="bg-base-200 border-2 border-base-300 z-50 w-48 shadow-brutal-sm">
                    <li>
                      <.link navigate={~p"/substrate"} class="font-terminal text-sm">
                        <.icon name="hero-cpu-chip" class="size-4" /> Dashboard
                      </.link>
                    </li>
                    <li>
                      <.link navigate={~p"/substrate/compare"} class="font-terminal text-sm">
                        <.icon name="hero-arrows-right-left" class="size-4" /> Divergence
                      </.link>
                    </li>
                    <li>
                      <.link navigate={~p"/substrate/thoughts"} class="font-terminal text-sm">
                        <.icon name="hero-sparkles" class="size-4" /> Thoughts
                      </.link>
                    </li>
                  </ul>
                </details>
              </li>
              <li>
                <details>
                  <summary class={[
                    "text-sm font-terminal",
                    nav_group_active?(assigns, ["/goals", "/actions"])
                  ]}>
                    <.icon name="hero-flag" class="size-4" /> Pursuit
                  </summary>
                  <ul class="bg-base-200 border-2 border-base-300 z-50 w-48 shadow-brutal-sm">
                    <li>
                      <.link navigate={~p"/goals"} class="font-terminal text-sm">
                        <.icon name="hero-flag" class="size-4" /> Goals
                      </.link>
                    </li>
                    <li>
                      <.link navigate={~p"/actions"} class="font-terminal text-sm">
                        <.icon name="hero-bolt" class="size-4" /> Actions
                      </.link>
                    </li>
                  </ul>
                </details>
              </li>
              <li>
                <details>
                  <summary class={[
                    "text-sm font-terminal",
                    nav_group_active?(assigns, [
                      "/beliefs",
                      "/questions",
                      "/memories",
                      "/narrative",
                      "/benchmarks"
                    ])
                  ]}>
                    <.icon name="hero-beaker" class="size-4" /> Research
                  </summary>
                  <ul class="bg-base-200 border-2 border-base-300 z-50 w-48 shadow-brutal-sm">
                    <li>
                      <.link navigate={~p"/beliefs"} class="font-terminal text-sm">
                        <.icon name="hero-light-bulb" class="size-4" /> Beliefs
                      </.link>
                    </li>
                    <li>
                      <.link navigate={~p"/questions"} class="font-terminal text-sm">
                        <.icon name="hero-question-mark-circle" class="size-4" /> Questions
                      </.link>
                    </li>
                    <li>
                      <.link navigate={~p"/memories"} class="font-terminal text-sm">
                        <.icon name="hero-archive-box" class="size-4" /> Memories
                      </.link>
                    </li>
                    <li>
                      <.link navigate={~p"/narrative"} class="font-terminal text-sm">
                        <.icon name="hero-book-open" class="size-4" /> Narrative
                      </.link>
                    </li>
                    <li>
                      <.link navigate={~p"/benchmarks"} class="font-terminal text-sm">
                        <.icon name="hero-chart-bar" class="size-4" /> Benchmarks
                      </.link>
                    </li>
                  </ul>
                </details>
              </li>
            </ul>
          </div>

          <div class="navbar-end gap-2">
            <div class="hidden sm:flex items-center gap-2 px-3 py-1 border-2 border-base-300 bg-base-300">
              <span class="status-dot status-dot-online"></span>
              <span class="text-xs font-terminal text-base-content/70">ONLINE</span>
            </div>
            <.link
              navigate={~p"/dev/dashboard"}
              class="btn btn-ghost btn-sm btn-square"
              title="System"
              aria-label="System settings"
            >
              <.icon name="hero-cog-6-tooth" class="size-5" />
            </.link>
            <.theme_toggle />
          </div>
        </div>

        <%!-- Page content --%>
        <main class="flex-1 p-3 sm:p-4 lg:p-6">
          <div class="mx-auto max-w-7xl">
            {render_slot(@inner_block)}
          </div>
        </main>

        <%!-- Footer --%>
        <footer class="bg-base-200 border-t-2 border-base-300 px-4 py-3">
          <div class="flex items-center justify-center gap-4 text-xs font-terminal text-base-content/40 uppercase">
            <span>Lincoln v0.1.0</span>
            <span class="text-base-content/15">|</span>
            <span>Neural Learning Agent</span>
            <span class="text-base-content/15">|</span>
            <span class="flex items-center gap-1.5">
              Session Active <span class="status-dot status-dot-online"></span>
            </span>
          </div>
        </footer>
      </div>

      <%!-- Sidebar drawer --%>
      <div class="drawer-side z-40">
        <label for="lincoln-drawer" aria-label="close sidebar" class="drawer-overlay"></label>
        <aside class="bg-base-200 min-h-full w-64 border-r-2 border-base-300 flex flex-col">
          <%!-- Sidebar header --%>
          <div class="p-4 border-b-2 border-base-300 scan-lines">
            <div class="flex items-center gap-3">
              <div class="w-10 h-10 bg-primary text-primary-content flex items-center justify-center border-2 border-primary shadow-brutal-sm">
                <span class="text-lg font-terminal font-bold">L</span>
              </div>
              <div>
                <h2 class="font-terminal font-bold uppercase tracking-tight">Lincoln</h2>
                <p class="text-[10px] font-terminal text-base-content/50 uppercase tracking-wider">
                  Neural Learning System
                </p>
              </div>
            </div>
          </div>

          <%!-- Navigation menu --%>
          <nav class="flex-1 overflow-y-auto p-3">
            <ul class="menu gap-0.5">
              <li class="menu-title">
                <span class="text-[10px] font-terminal uppercase tracking-widest text-base-content/40">
                  Navigation
                </span>
              </li>
              <li>
                <.link navigate={~p"/"} class={sidebar_class(assigns, "/")}>
                  <.icon name="hero-squares-2x2" class="size-4" /> Dashboard
                </.link>
              </li>
              <li>
                <.link navigate={~p"/chat"} class={sidebar_class(assigns, "/chat")}>
                  <.icon name="hero-chat-bubble-left-right" class="size-4" /> Chat
                </.link>
              </li>

              <li class="menu-title mt-4">
                <span class="text-[10px] font-terminal uppercase tracking-widest text-base-content/40">
                  Substrate
                </span>
              </li>
              <li>
                <.link navigate={~p"/substrate"} class={sidebar_class(assigns, "/substrate")}>
                  <.icon name="hero-cpu-chip" class="size-4" /> Dashboard
                </.link>
              </li>
              <li>
                <.link
                  navigate={~p"/substrate/compare"}
                  class={sidebar_class(assigns, "/substrate/compare")}
                >
                  <.icon name="hero-arrows-right-left" class="size-4" /> Divergence
                </.link>
              </li>
              <li>
                <.link
                  navigate={~p"/substrate/thoughts"}
                  class={sidebar_class(assigns, "/substrate/thoughts")}
                >
                  <.icon name="hero-sparkles" class="size-4" /> Thoughts
                </.link>
              </li>

              <li class="menu-title mt-4">
                <span class="text-[10px] font-terminal uppercase tracking-widest text-base-content/40">
                  Pursuit
                </span>
              </li>
              <li>
                <.link navigate={~p"/goals"} class={sidebar_class(assigns, "/goals")}>
                  <.icon name="hero-flag" class="size-4" /> Goals
                </.link>
              </li>
              <li>
                <.link navigate={~p"/actions"} class={sidebar_class(assigns, "/actions")}>
                  <.icon name="hero-bolt" class="size-4" /> Actions
                </.link>
              </li>

              <li class="menu-title mt-4">
                <span class="text-[10px] font-terminal uppercase tracking-widest text-base-content/40">
                  Research
                </span>
              </li>
              <li>
                <.link navigate={~p"/beliefs"} class={sidebar_class(assigns, "/beliefs")}>
                  <.icon name="hero-light-bulb" class="size-4" /> Beliefs
                </.link>
              </li>
              <li>
                <.link navigate={~p"/questions"} class={sidebar_class(assigns, "/questions")}>
                  <.icon name="hero-question-mark-circle" class="size-4" /> Questions
                </.link>
              </li>
              <li>
                <.link navigate={~p"/memories"} class={sidebar_class(assigns, "/memories")}>
                  <.icon name="hero-archive-box" class="size-4" /> Memories
                </.link>
              </li>
              <li>
                <.link navigate={~p"/narrative"} class={sidebar_class(assigns, "/narrative")}>
                  <.icon name="hero-book-open" class="size-4" /> Narrative
                </.link>
              </li>
              <li>
                <.link navigate={~p"/benchmarks"} class={sidebar_class(assigns, "/benchmarks")}>
                  <.icon name="hero-chart-bar" class="size-4" /> Benchmarks
                </.link>
              </li>

              <li class="menu-title mt-4">
                <span class="text-[10px] font-terminal uppercase tracking-widest text-base-content/40">
                  System
                </span>
              </li>
              <li>
                <.link navigate={~p"/dev/dashboard"} class={sidebar_class(assigns, "/dev/dashboard")}>
                  <.icon name="hero-cog-6-tooth" class="size-4" /> Settings
                </.link>
              </li>
            </ul>
          </nav>

          <%!-- Sidebar footer --%>
          <div class="p-3 border-t-2 border-base-300">
            <div class="flex items-center justify-between text-xs font-terminal text-base-content/40 uppercase">
              <span>Theme</span>
              <.theme_toggle />
            </div>
          </div>
        </aside>
      </div>
    </div>

    <.flash_group flash={@flash} />
    """
  end

  # Navigation active state helpers

  defp nav_active?(assigns, path) do
    current = assigns[:current_path]

    cond do
      is_nil(current) -> nil
      path == "/" -> if current == "/", do: "font-bold text-primary"
      String.starts_with?(current, path) -> "font-bold text-primary"
      true -> nil
    end
  end

  defp nav_group_active?(assigns, paths) when is_list(paths) do
    current = assigns[:current_path]

    if current && Enum.any?(paths, &String.starts_with?(current, &1)) do
      "font-bold text-primary"
    end
  end

  defp nav_group_active?(assigns, prefix) do
    current = assigns[:current_path]

    if current && String.starts_with?(current, prefix) do
      "font-bold text-primary"
    end
  end

  defp sidebar_class(assigns, path) do
    current = assigns[:current_path]
    base = "font-terminal text-sm"

    active? =
      cond do
        is_nil(current) -> false
        path == "/" -> current == "/"
        true -> String.starts_with?(current, path)
      end

    if active? do
      "#{base} font-bold text-primary border-l-3 border-primary bg-primary/8"
    else
      "#{base} hover:bg-base-300"
    end
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

  @doc """
  Theme toggle using daisyUI swap component with theme-controller.
  """
  def theme_toggle(assigns) do
    ~H"""
    <label class="swap swap-rotate btn btn-ghost btn-sm btn-square" aria-label="Toggle theme">
      <input type="checkbox" class="theme-controller" value="lincoln-light" />
      <svg
        class="swap-off size-5 fill-current"
        xmlns="http://www.w3.org/2000/svg"
        viewBox="0 0 24 24"
      >
        <path d="M5.64,17l-.71.71a1,1,0,0,0,0,1.41,1,1,0,0,0,1.41,0l.71-.71A1,1,0,0,0,5.64,17ZM5,12a1,1,0,0,0-1-1H3a1,1,0,0,0,0,2H4A1,1,0,0,0,5,12Zm7-7a1,1,0,0,0,1-1V3a1,1,0,0,0-2,0V4A1,1,0,0,0,12,5ZM5.64,7.05a1,1,0,0,0,.7.29,1,1,0,0,0,.71-.29,1,1,0,0,0,0-1.41l-.71-.71A1,1,0,0,0,4.93,6.34Zm12,.29a1,1,0,0,0,.7-.29l.71-.71a1,1,0,1,0-1.41-1.41L17,5.64a1,1,0,0,0,0,1.41A1,1,0,0,0,17.66,7.34ZM21,11H20a1,1,0,0,0,0,2h1a1,1,0,0,0,0-2Zm-9,8a1,1,0,0,0-1,1v1a1,1,0,0,0,2,0V20A1,1,0,0,0,12,19ZM18.36,17A1,1,0,0,0,17,18.36l.71.71a1,1,0,0,0,1.41,0,1,1,0,0,0,0-1.41ZM12,6.5A5.5,5.5,0,1,0,17.5,12,5.51,5.51,0,0,0,12,6.5Zm0,9A3.5,3.5,0,1,1,15.5,12,3.5,3.5,0,0,1,12,15.5Z" />
      </svg>
      <svg
        class="swap-on size-5 fill-current"
        xmlns="http://www.w3.org/2000/svg"
        viewBox="0 0 24 24"
      >
        <path d="M21.64,13a1,1,0,0,0-1.05-.14,8.05,8.05,0,0,1-3.37.73A8.15,8.15,0,0,1,9.08,5.49a8.59,8.59,0,0,1,.25-2A1,1,0,0,0,8,2.36,10.14,10.14,0,1,0,22,14.05,1,1,0,0,0,21.64,13Zm-9.5,6.69A8.14,8.14,0,0,1,7.08,5.22v.27A10.15,10.15,0,0,0,17.22,15.63a9.79,9.79,0,0,0,2.1-.22A8.11,8.11,0,0,1,12.14,19.73Z" />
      </svg>
    </label>
    """
  end
end
