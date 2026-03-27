defmodule LincolnWeb.Layouts do
  @moduledoc """
  This module holds layouts and related functionality.

  Lincoln Neural Terminal - daisyUI Cyberpunk Theme
  Uses drawer + navbar pattern for responsive navigation.
  """
  use LincolnWeb, :html

  embed_templates("layouts/*")

  @doc """
  Renders your app layout with drawer navigation.
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
      
    <!-- Main content area -->
      <div class="drawer-content flex flex-col min-h-screen neural-grid">
        <!-- Navbar -->
        <div class="navbar bg-base-200 border-b-2 border-primary sticky top-0 z-30">
          <div class="navbar-start">
            <!-- Mobile drawer toggle -->
            <label for="lincoln-drawer" class="btn btn-ghost btn-square lg:hidden">
              <.icon name="hero-bars-3" class="size-5" />
            </label>
            <!-- Logo -->
            <a href="/" class="btn btn-ghost gap-2 text-xl font-terminal uppercase">
              <div class="relative">
                <.icon name="hero-cpu-chip" class="size-6 text-primary" />
                <span class="absolute -top-1 -right-1 size-2 bg-accent neural-pulse"></span>
              </div>
              <span class="hidden sm:inline">Lincoln<span class="cursor-blink"></span></span>
            </a>
          </div>

          <div class="navbar-center hidden lg:flex">
            <ul class="menu menu-horizontal gap-1">
              <li>
                <a href="/" class="font-terminal uppercase text-sm">
                  <.icon name="hero-squares-2x2" class="size-4" /> Dashboard
                </a>
              </li>
              <li>
                <a href="/chat" class="font-terminal uppercase text-sm">
                  <.icon name="hero-chat-bubble-left-right" class="size-4" /> Chat
                </a>
              </li>
              <li>
                <a href="/beliefs" class="font-terminal uppercase text-sm">
                  <.icon name="hero-light-bulb" class="size-4" /> Beliefs
                </a>
              </li>
              <li>
                <a href="/questions" class="font-terminal uppercase text-sm">
                  <.icon name="hero-question-mark-circle" class="size-4" /> Questions
                </a>
              </li>
              <li>
                <a href="/memories" class="font-terminal uppercase text-sm">
                  <.icon name="hero-archive-box" class="size-4" /> Memories
                </a>
              </li>
              <li>
                <a href="/autonomy" class="font-terminal uppercase text-sm">
                  <.icon name="hero-bolt" class="size-4" /> Autonomy
                </a>
              </li>
            </ul>
          </div>

          <div class="navbar-end gap-2">
            <!-- System status -->
            <div class="hidden sm:flex items-center gap-2 px-3 py-1 bg-base-300 border border-primary/30">
              <span class="status status-success status-glow"></span>
              <span class="font-terminal text-xs uppercase text-primary/70">Online</span>
            </div>
            
    <!-- System link -->
            <a href="/dev/dashboard" class="btn btn-ghost btn-sm btn-square" title="System">
              <.icon name="hero-cog-6-tooth" class="size-5" />
            </a>
            
    <!-- Theme toggle -->
            <.theme_toggle />
          </div>
        </div>
        
    <!-- Scan line effect -->
        <div class="h-px scan-line"></div>
        
    <!-- Page content -->
        <main class="flex-1 p-4 sm:p-6 lg:p-8">
          <div class="mx-auto max-w-7xl">
            {render_slot(@inner_block)}
          </div>
        </main>
        
    <!-- Footer -->
        <footer class="footer footer-center bg-base-200 border-t-2 border-primary/20 p-4">
          <div class="flex items-center gap-4 text-xs font-terminal text-base-content/40">
            <span>LINCOLN v0.1.0</span>
            <span class="w-8 h-px bg-gradient-to-r from-transparent via-primary/50 to-transparent">
            </span>
            <span>Neural Learning Agent</span>
            <span class="w-8 h-px bg-gradient-to-r from-transparent via-primary/50 to-transparent">
            </span>
            <div class="flex items-center gap-1">
              <span class="uppercase">Session Active</span>
              <span class="status status-success neural-pulse"></span>
            </div>
          </div>
        </footer>
      </div>
      
    <!-- Sidebar drawer -->
      <div class="drawer-side z-40">
        <label for="lincoln-drawer" aria-label="close sidebar" class="drawer-overlay"></label>
        <aside class="bg-base-200 min-h-full w-72 border-r-2 border-primary">
          <!-- Sidebar header -->
          <div class="p-4 border-b-2 border-primary">
            <div class="flex items-center gap-3">
              <div class="avatar placeholder">
                <div class="bg-primary text-primary-content w-12 border-2 border-primary shadow-brutal-sm">
                  <span class="text-xl font-black font-terminal">L</span>
                </div>
              </div>
              <div>
                <h2 class="font-terminal font-bold uppercase">Lincoln</h2>
                <p class="text-xs font-terminal text-base-content/60">Neural Learning System</p>
              </div>
            </div>
          </div>
          
    <!-- Navigation menu -->
          <ul class="menu p-4 gap-1">
            <li class="menu-title font-terminal uppercase text-xs tracking-wider">
              <span>Navigation</span>
            </li>
            <li>
              <a href="/" class="font-terminal uppercase">
                <.icon name="hero-squares-2x2" class="size-5" /> Dashboard
              </a>
            </li>
            <li>
              <a href="/chat" class="font-terminal uppercase">
                <.icon name="hero-chat-bubble-left-right" class="size-5" /> Chat
                <span class="badge badge-primary badge-sm">Talk</span>
              </a>
            </li>
            <li>
              <a href="/beliefs" class="font-terminal uppercase">
                <.icon name="hero-light-bulb" class="size-5" /> Beliefs
                <span class="badge badge-secondary badge-sm">Matrix</span>
              </a>
            </li>
            <li>
              <a href="/questions" class="font-terminal uppercase">
                <.icon name="hero-question-mark-circle" class="size-5" /> Questions
                <span class="badge badge-accent badge-sm">Query</span>
              </a>
            </li>
            <li>
              <a href="/memories" class="font-terminal uppercase">
                <.icon name="hero-archive-box" class="size-5" /> Memories
                <span class="badge badge-info badge-sm">Bank</span>
              </a>
            </li>
            <li>
              <a href="/autonomy" class="font-terminal uppercase">
                <.icon name="hero-bolt" class="size-5" /> Autonomy
                <span class="badge badge-warning badge-sm">Night</span>
              </a>
            </li>

            <li class="menu-title font-terminal uppercase text-xs tracking-wider mt-4">
              <span>System</span>
            </li>
            <li>
              <a href="/dev/dashboard" class="font-terminal uppercase">
                <.icon name="hero-cog-6-tooth" class="size-5" /> Settings
              </a>
            </li>
          </ul>
          
    <!-- Sidebar footer -->
          <div class="absolute bottom-0 left-0 right-0 p-4 border-t border-primary/20">
            <div class="flex items-center justify-between text-xs font-terminal text-base-content/50">
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
        <span class="flex items-center gap-2">
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
        <span class="flex items-center gap-2">
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
    <label class="swap swap-rotate btn btn-ghost btn-sm btn-square">
      <!-- Hidden checkbox controls theme -->
      <input type="checkbox" class="theme-controller" value="light" />
      
    <!-- Sun icon (shown when dark/cyberpunk theme is active) -->
      <svg
        class="swap-off size-5 fill-current"
        xmlns="http://www.w3.org/2000/svg"
        viewBox="0 0 24 24"
      >
        <path d="M5.64,17l-.71.71a1,1,0,0,0,0,1.41,1,1,0,0,0,1.41,0l.71-.71A1,1,0,0,0,5.64,17ZM5,12a1,1,0,0,0-1-1H3a1,1,0,0,0,0,2H4A1,1,0,0,0,5,12Zm7-7a1,1,0,0,0,1-1V3a1,1,0,0,0-2,0V4A1,1,0,0,0,12,5ZM5.64,7.05a1,1,0,0,0,.7.29,1,1,0,0,0,.71-.29,1,1,0,0,0,0-1.41l-.71-.71A1,1,0,0,0,4.93,6.34Zm12,.29a1,1,0,0,0,.7-.29l.71-.71a1,1,0,1,0-1.41-1.41L17,5.64a1,1,0,0,0,0,1.41A1,1,0,0,0,17.66,7.34ZM21,11H20a1,1,0,0,0,0,2h1a1,1,0,0,0,0-2Zm-9,8a1,1,0,0,0-1,1v1a1,1,0,0,0,2,0V20A1,1,0,0,0,12,19ZM18.36,17A1,1,0,0,0,17,18.36l.71.71a1,1,0,0,0,1.41,0,1,1,0,0,0,0-1.41ZM12,6.5A5.5,5.5,0,1,0,17.5,12,5.51,5.51,0,0,0,12,6.5Zm0,9A3.5,3.5,0,1,1,15.5,12,3.5,3.5,0,0,1,12,15.5Z" />
      </svg>
      
    <!-- Moon icon (shown when light theme is active) -->
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
