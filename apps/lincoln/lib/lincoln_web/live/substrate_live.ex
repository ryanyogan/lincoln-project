defmodule LincolnWeb.SubstrateLive do
  @moduledoc """
  Real-time cognitive substrate dashboard.

  Shows live state of the agent's substrate process: tick counter,
  current focus, pending events, driver activity, and a scrollable
  event timeline — all updated via PubSub.
  """
  use LincolnWeb, :live_view

  alias Lincoln.{Agents, Substrate}
  alias Lincoln.PubSubBroadcaster

  @impl true
  def mount(_params, _session, socket) do
    {:ok, agent} = Agents.get_or_create_default_agent()

    substrate_state =
      case Substrate.get_agent_state(agent.id) do
        {:ok, state} -> state
        {:error, _} -> nil
      end

    socket =
      socket
      |> assign(:agent, agent)
      |> assign(:page_title, "Cognitive Substrate")
      |> assign(:substrate_state, substrate_state)
      |> assign(:substrate_running, substrate_state != nil)
      |> assign(:recent_events, [])

    if connected?(socket) do
      Phoenix.PubSub.subscribe(Lincoln.PubSub, PubSubBroadcaster.substrate_topic(agent.id))
      Phoenix.PubSub.subscribe(Lincoln.PubSub, PubSubBroadcaster.driver_topic(agent.id))
      Phoenix.PubSub.subscribe(Lincoln.PubSub, PubSubBroadcaster.attention_topic(agent.id))
    end

    {:ok, socket}
  end

  @impl true
  def handle_params(_params, _uri, socket) do
    {:noreply, socket}
  end

  # ============================================================================
  # PubSub Handlers
  # ============================================================================

  @impl true
  def handle_info({:tick, tick_count, current_focus}, socket) do
    substrate_state =
      case Substrate.get_agent_state(socket.assigns.agent.id) do
        {:ok, state} -> state
        {:error, _} -> nil
      end

    event_entry = %{
      time: DateTime.utc_now(),
      type: :tick,
      tick_count: tick_count,
      focus: current_focus && current_focus.statement
    }

    recent = [event_entry | socket.assigns.recent_events] |> Enum.take(20)

    {:noreply,
     socket
     |> assign(:substrate_state, substrate_state)
     |> assign(:substrate_running, substrate_state != nil)
     |> assign(:recent_events, recent)}
  end

  def handle_info({:executed, action}, socket) do
    event_entry = %{
      time: DateTime.utc_now(),
      type: :driver_action,
      action: action
    }

    recent = [event_entry | socket.assigns.recent_events] |> Enum.take(20)
    {:noreply, assign(socket, :recent_events, recent)}
  end

  # Catch-all for other PubSub messages
  def handle_info(_msg, socket), do: {:noreply, socket}

  # ============================================================================
  # Render
  # ============================================================================

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash}>
      <div class="space-y-6">
        <%!-- Page Header --%>
        <div class="flex items-center justify-between">
          <div class="flex items-center gap-3">
            <div class="relative">
              <.icon name="hero-cpu-chip" class="size-8 text-primary" />
              <span class={[
                "absolute -bottom-0.5 -right-0.5 size-2.5 rounded-full border-2 border-base-100",
                if(@substrate_running, do: "bg-success", else: "bg-error")
              ]}>
              </span>
            </div>
            <div>
              <h1 class="text-2xl font-black font-terminal uppercase tracking-tight">
                Cognitive Substrate
              </h1>
              <p class="text-base-content/50 text-sm font-terminal">
                Real-time process state for {@agent.name}
              </p>
            </div>
          </div>
          <span class={[
            "badge font-terminal font-bold uppercase text-xs",
            if(@substrate_running, do: "badge-success", else: "badge-error")
          ]}>
            <span class={[
              "size-2 rounded-full mr-1.5",
              if(@substrate_running, do: "bg-success-content animate-pulse", else: "bg-error-content")
            ]}>
            </span>
            <%= if @substrate_running do %>
              Running
            <% else %>
              Offline
            <% end %>
          </span>
        </div>

        <%= if @substrate_running do %>
          <%!-- Main 2-column grid --%>
          <div class="grid lg:grid-cols-3 gap-6">
            <%!-- Left column: Status + Driver (2/3 width) --%>
            <div class="lg:col-span-2 space-y-6">
              <%!-- Substrate Status Card --%>
              <div class="card bg-base-200 border-2 border-primary/50 hover:border-primary transition-colors neural-card">
                <div class="card-body p-0">
                  <div class="flex items-center justify-between px-4 py-3 border-b-2 border-primary/30 bg-base-300">
                    <h2 class="card-title text-sm font-terminal uppercase gap-2">
                      <.icon name="hero-cpu-chip" class="size-4 text-primary" /> Substrate State
                    </h2>
                    <span class="text-xs font-terminal text-base-content/40">
                      Since {format_time(@substrate_state.started_at)}
                    </span>
                  </div>

                  <div class="p-4">
                    <%!-- Stats row --%>
                    <div class="stats stats-vertical sm:stats-horizontal bg-base-300 w-full border border-primary/20">
                      <div class="stat">
                        <div class="stat-figure text-primary">
                          <.icon name="hero-arrow-path" class="size-7 neural-pulse" />
                        </div>
                        <div class="stat-title font-terminal uppercase text-xs">Tick</div>
                        <div class="stat-value text-primary font-terminal">
                          {@substrate_state.tick_count}
                        </div>
                        <div class="stat-desc font-terminal">
                          <%= if @substrate_state.last_tick_at do %>
                            Last: {format_time(@substrate_state.last_tick_at)}
                          <% else %>
                            Awaiting first tick
                          <% end %>
                        </div>
                      </div>

                      <div class="stat">
                        <div class="stat-figure text-warning">
                          <.icon name="hero-inbox-stack" class="size-7" />
                        </div>
                        <div class="stat-title font-terminal uppercase text-xs">Pending</div>
                        <div class="stat-value text-warning font-terminal">
                          {length(@substrate_state.pending_events)}
                        </div>
                        <div class="stat-desc font-terminal">Events queued</div>
                      </div>

                      <div class="stat">
                        <div class="stat-figure text-secondary">
                          <.icon name="hero-clock" class="size-7" />
                        </div>
                        <div class="stat-title font-terminal uppercase text-xs">Interval</div>
                        <div class="stat-value text-secondary font-terminal text-lg">
                          {div(@substrate_state.tick_interval, 1000)}s
                        </div>
                        <div class="stat-desc font-terminal">Tick frequency</div>
                      </div>
                    </div>

                    <%!-- Current Focus --%>
                    <div class="mt-4 p-3 bg-base-300 border border-accent/30">
                      <div class="flex items-center gap-2 mb-2">
                        <span class="node-indicator active"></span>
                        <span class="text-xs font-terminal uppercase text-base-content/60">Current Focus</span>
                      </div>
                      <%= if @substrate_state.current_focus do %>
                        <p class="text-sm font-terminal text-accent leading-relaxed">
                          {@substrate_state.current_focus.statement}
                        </p>
                        <div class="flex items-center gap-2 mt-2">
                          <span class="badge badge-accent badge-xs font-terminal">
                            {Float.round(@substrate_state.current_focus.confidence * 100, 0)}%
                          </span>
                          <span class="text-[10px] font-terminal text-base-content/40">
                            E:{@substrate_state.current_focus.entrenchment}
                          </span>
                        </div>
                      <% else %>
                        <p class="text-sm font-terminal text-base-content/40 italic">
                          Idle — no belief in focus
                        </p>
                      <% end %>
                    </div>
                  </div>
                </div>
              </div>

              <%!-- Driver Activity Card --%>
              <div class="card bg-base-200 border-2 border-info/50 hover:border-info transition-colors">
                <div class="card-body p-0">
                  <div class="flex items-center justify-between px-4 py-3 border-b-2 border-info/30 bg-base-300">
                    <h2 class="card-title text-sm font-terminal uppercase gap-2">
                      <.icon name="hero-play" class="size-4 text-info" /> Driver Activity
                    </h2>
                  </div>
                  <div class="p-4">
                    <.driver_status events={@recent_events} />
                  </div>
                </div>
              </div>
            </div>

            <%!-- Right column: Event Timeline (1/3 width) --%>
            <div class="lg:col-span-1">
              <div class="card bg-base-200 border-2 border-secondary/50 hover:border-secondary transition-colors h-full">
                <div class="card-body p-0">
                  <div class="px-4 py-3 border-b-2 border-secondary/30 bg-base-300">
                    <h2 class="card-title text-sm font-terminal uppercase gap-2">
                      <.icon name="hero-signal" class="size-4 text-secondary" /> Event Stream
                    </h2>
                  </div>
                  <div class="p-3 max-h-[32rem] overflow-y-auto">
                    <%= if @recent_events == [] do %>
                      <div class="flex flex-col items-center justify-center py-12 text-base-content/40">
                        <.icon name="hero-signal" class="size-8 mb-2" />
                        <p class="text-sm font-terminal">Waiting for events...</p>
                      </div>
                    <% else %>
                      <ul class="space-y-1.5">
                        <li :for={event <- @recent_events}>
                          <.event_entry event={event} />
                        </li>
                      </ul>
                    <% end %>
                  </div>
                </div>
              </div>
            </div>
          </div>
        <% else %>
          <%!-- Empty State --%>
          <div class="card bg-base-200 border-2 border-base-300">
            <div class="card-body">
              <div class="text-center py-16">
                <div class="relative inline-block mb-4">
                  <.icon name="hero-cpu-chip" class="size-16 text-base-content/20" />
                </div>
                <p class="text-base-content/50 text-lg font-terminal">No active substrate</p>
                <p class="text-base-content/30 text-sm mt-2 font-terminal">
                  Start an agent to begin cognitive processing
                </p>
              </div>
            </div>
          </div>
        <% end %>
      </div>
    </Layouts.app>
    """
  end

  # ============================================================================
  # Component Functions
  # ============================================================================

  attr(:events, :list, required: true)

  defp driver_status(assigns) do
    last_action = Enum.find(assigns.events, &(&1.type == :driver_action))
    assigns = assign(assigns, :last_action, last_action)

    ~H"""
    <%= if @last_action do %>
      <div class="p-3 bg-base-300 border border-info/20">
        <div class="flex items-center gap-2 mb-1">
          <span class="node-indicator active"></span>
          <span class="text-xs font-terminal uppercase text-base-content/60">Last Action</span>
        </div>
        <p class="text-sm font-terminal text-info">
          {inspect(@last_action.action)}
        </p>
        <span class="text-[10px] font-terminal text-base-content/40 mt-1 block">
          {format_time(@last_action.time)}
        </span>
      </div>
    <% else %>
      <div class="flex flex-col items-center justify-center py-8 text-base-content/40">
        <.icon name="hero-pause" class="size-8 mb-2" />
        <p class="text-sm font-terminal">Driver idle — no recent actions</p>
      </div>
    <% end %>
    """
  end

  attr(:event, :map, required: true)

  defp event_entry(assigns) do
    ~H"""
    <div class={[
      "flex items-start gap-2 p-2 border transition-colors",
      event_style(@event.type)
    ]}>
      <div class="mt-0.5">
        <.event_icon type={@event.type} />
      </div>
      <div class="flex-1 min-w-0">
        <.event_body event={@event} />
        <span class="text-[10px] font-terminal text-base-content/30 block mt-0.5">
          {format_time(@event.time)}
        </span>
      </div>
    </div>
    """
  end

  attr(:type, :atom, required: true)

  defp event_icon(assigns) do
    ~H"""
    <%= case @type do %>
      <% :tick -> %>
        <.icon name="hero-arrow-path" class="size-3.5 text-primary/70" />
      <% :driver_action -> %>
        <.icon name="hero-play" class="size-3.5 text-info/70" />
      <% _ -> %>
        <.icon name="hero-signal" class="size-3.5 text-base-content/40" />
    <% end %>
    """
  end

  attr(:event, :map, required: true)

  defp event_body(assigns) do
    ~H"""
    <%= case @event.type do %>
      <% :tick -> %>
        <p class="text-xs font-terminal">
          <span class="text-primary">Tick {@event.tick_count}</span>
          <%= if @event.focus do %>
            <span class="text-base-content/50"> — </span>
            <span class="text-base-content/60 line-clamp-1">{truncate(@event.focus, 40)}</span>
          <% end %>
        </p>
      <% :driver_action -> %>
        <p class="text-xs font-terminal">
          <span class="text-info">Action</span>
          <span class="text-base-content/60"> {inspect(@event.action)}</span>
        </p>
      <% _ -> %>
        <p class="text-xs font-terminal text-base-content/50">Unknown event</p>
    <% end %>
    """
  end

  # ============================================================================
  # Helpers
  # ============================================================================

  defp event_style(:tick), do: "bg-base-300/50 border-primary/10 hover:border-primary/30"
  defp event_style(:driver_action), do: "bg-base-300/50 border-info/10 hover:border-info/30"
  defp event_style(_), do: "bg-base-300/50 border-base-content/5"

  defp format_time(%DateTime{} = dt) do
    Calendar.strftime(dt, "%H:%M:%S")
  end

  defp format_time(_), do: "-"

  defp truncate(text, max) when is_binary(text) do
    if String.length(text) > max do
      String.slice(text, 0, max) <> "..."
    else
      text
    end
  end

  defp truncate(_, _), do: ""
end
