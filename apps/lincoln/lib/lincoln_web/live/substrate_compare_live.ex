defmodule LincolnWeb.SubstrateCompareLive do
  @moduledoc """
  Side-by-side comparison of two cognitive substrates diverging in real time.

  The demo page — select two agents and watch their focus, tick counts,
  and event streams diverge independently as each substrate processes
  the same world through different attention parameters.
  """
  use LincolnWeb, :live_view

  alias Lincoln.{Agents, Substrate}
  alias Lincoln.PubSubBroadcaster

  @max_events 30

  @impl true
  def mount(_params, _session, socket) do
    agents = Agents.list_agents()

    socket =
      socket
      |> assign(:page_title, "Divergence Observatory")
      |> assign(:agents, agents)
      |> assign(:agent_a_id, nil)
      |> assign(:agent_b_id, nil)
      |> assign(:agent_a_state, nil)
      |> assign(:agent_b_state, nil)
      |> assign(:events_a, [])
      |> assign(:events_b, [])

    {:ok, socket}
  end

  @impl true
  def handle_params(_params, _uri, socket) do
    {:noreply, socket}
  end

  # ============================================================================
  # Events
  # ============================================================================

  @impl true
  def handle_event("select_agents", %{"agent_a" => a_id, "agent_b" => b_id}, socket) do
    # Unsubscribe from previous agents
    unsubscribe_agent(socket.assigns.agent_a_id)
    unsubscribe_agent(socket.assigns.agent_b_id)

    # Subscribe to new agents
    if connected?(socket) do
      Phoenix.PubSub.subscribe(Lincoln.PubSub, PubSubBroadcaster.substrate_topic(a_id))
      Phoenix.PubSub.subscribe(Lincoln.PubSub, PubSubBroadcaster.driver_topic(a_id))
      Phoenix.PubSub.subscribe(Lincoln.PubSub, PubSubBroadcaster.substrate_topic(b_id))
      Phoenix.PubSub.subscribe(Lincoln.PubSub, PubSubBroadcaster.driver_topic(b_id))
    end

    state_a = fetch_state(a_id)
    state_b = fetch_state(b_id)

    {:noreply,
     socket
     |> assign(:agent_a_id, a_id)
     |> assign(:agent_b_id, b_id)
     |> assign(:agent_a_state, state_a)
     |> assign(:agent_b_state, state_b)
     |> assign(:events_a, [])
     |> assign(:events_b, [])}
  end

  # ============================================================================
  # PubSub Handlers
  # ============================================================================

  # Since {:tick, count, focus} doesn't include agent_id, refresh both states
  # on every tick. This is cheap (Registry lookup + GenServer.call) and ensures
  # both panels stay in sync.
  @impl true
  def handle_info({:tick, tick_count, current_focus}, socket) do
    prev_a = socket.assigns.agent_a_state
    prev_b = socket.assigns.agent_b_state

    new_a = fetch_state(socket.assigns.agent_a_id) || prev_a
    new_b = fetch_state(socket.assigns.agent_b_id) || prev_b

    # Determine which agent ticked by comparing tick counts to previous
    events_a =
      if new_a && prev_a && new_a.tick_count != prev_a.tick_count do
        event = %{
          time: DateTime.utc_now(),
          type: :tick,
          tick_count: new_a.tick_count,
          focus: focus_label(new_a.current_focus)
        }

        prepend_event(socket.assigns.events_a, event)
      else
        socket.assigns.events_a
      end

    events_b =
      if new_b && prev_b && new_b.tick_count != prev_b.tick_count do
        event = %{
          time: DateTime.utc_now(),
          type: :tick,
          tick_count: new_b.tick_count,
          focus: focus_label(new_b.current_focus)
        }

        prepend_event(socket.assigns.events_b, event)
      else
        socket.assigns.events_b
      end

    # First tick case — no previous state
    {events_a, events_b} =
      cond do
        prev_a == nil and new_a != nil ->
          event = %{
            time: DateTime.utc_now(),
            type: :tick,
            tick_count: tick_count,
            focus: focus_label(current_focus)
          }

          {prepend_event(events_a, event), events_b}

        prev_b == nil and new_b != nil ->
          event = %{
            time: DateTime.utc_now(),
            type: :tick,
            tick_count: tick_count,
            focus: focus_label(current_focus)
          }

          {events_a, prepend_event(events_b, event)}

        true ->
          {events_a, events_b}
      end

    {:noreply,
     socket
     |> assign(:agent_a_state, new_a)
     |> assign(:agent_b_state, new_b)
     |> assign(:events_a, events_a)
     |> assign(:events_b, events_b)}
  end

  def handle_info({:executed, action}, socket) do
    # Route driver actions by refreshing states and checking which changed
    new_a = fetch_state(socket.assigns.agent_a_id)
    new_b = fetch_state(socket.assigns.agent_b_id)

    event = %{time: DateTime.utc_now(), type: :driver_action, action: action}

    # Append to both since we can't distinguish source — driver events are rare
    events_a =
      if new_a, do: prepend_event(socket.assigns.events_a, event), else: socket.assigns.events_a

    {:noreply,
     socket
     |> assign(:agent_a_state, new_a || socket.assigns.agent_a_state)
     |> assign(:agent_b_state, new_b || socket.assigns.agent_b_state)
     |> assign(:events_a, events_a)}
  end

  # Catch-all for other PubSub messages (attention, skeptic, resonator)
  def handle_info(_msg, socket), do: {:noreply, socket}

  # ============================================================================
  # Render
  # ============================================================================

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash}>
      <div class="space-y-6">
        <%!-- Header --%>
        <div class="flex items-center justify-between">
          <div class="flex items-center gap-3">
            <div class="relative">
              <.icon name="hero-arrows-right-left" class="size-8 text-primary" />
            </div>
            <div>
              <h1 class="text-2xl font-black font-terminal uppercase tracking-tight">
                Divergence Observatory
              </h1>
              <p class="text-base-content/50 text-sm font-terminal">
                Watch two cognitive substrates diverge on identical inputs
              </p>
            </div>
          </div>
          <.link
            navigate={~p"/substrate"}
            class="btn btn-sm bg-base-300 border-base-content/10 font-terminal text-xs uppercase"
          >
            <.icon name="hero-cpu-chip" class="size-3.5" /> Single View
          </.link>
        </div>

        <%!-- Agent Selector --%>
        <div class="card bg-base-200 border-2 border-primary/30">
          <div class="card-body p-4">
            <.form for={to_form(%{}, as: :agents)} phx-submit="select_agents" id="agent-selector">
              <div class="flex items-end gap-4">
                <div class="flex-1">
                  <label class="text-xs font-terminal uppercase text-primary/70 mb-1 block">
                    Agent A
                  </label>
                  <select
                    name="agent_a"
                    class="select select-bordered w-full bg-base-300 border-primary/20 font-terminal text-sm focus:border-primary focus:outline-none"
                  >
                    <option value="">— select agent —</option>
                    <%= for agent <- @agents do %>
                      <option value={agent.id} selected={agent.id == @agent_a_id}>
                        {agent.name}
                      </option>
                    <% end %>
                  </select>
                </div>

                <div class="flex items-center justify-center pb-2">
                  <.icon name="hero-arrows-right-left" class="size-5 text-base-content/30" />
                </div>

                <div class="flex-1">
                  <label class="text-xs font-terminal uppercase text-secondary/70 mb-1 block">
                    Agent B
                  </label>
                  <select
                    name="agent_b"
                    class="select select-bordered w-full bg-base-300 border-secondary/20 font-terminal text-sm focus:border-secondary focus:outline-none"
                  >
                    <option value="">— select agent —</option>
                    <%= for agent <- @agents do %>
                      <option value={agent.id} selected={agent.id == @agent_b_id}>
                        {agent.name}
                      </option>
                    <% end %>
                  </select>
                </div>

                <button
                  type="submit"
                  class="btn bg-primary/20 border-primary/50 hover:bg-primary/30 text-primary font-terminal uppercase text-xs"
                >
                  <.icon name="hero-eye" class="size-4" /> Observe
                </button>
              </div>
            </.form>
          </div>
        </div>

        <%!-- Comparison Panels --%>
        <%= if @agent_a_id && @agent_b_id do %>
          <%!-- Divergence Indicator --%>
          <.divergence_bar
            focus_a={@agent_a_state && @agent_a_state.current_focus}
            focus_b={@agent_b_state && @agent_b_state.current_focus}
          />

          <div class="grid lg:grid-cols-2 gap-6">
            <%!-- Agent A --%>
            <.agent_panel
              label="A"
              color="primary"
              agent_name={get_agent_name(@agents, @agent_a_id)}
              state={@agent_a_state}
              events={@events_a}
            />

            <%!-- Agent B --%>
            <.agent_panel
              label="B"
              color="secondary"
              agent_name={get_agent_name(@agents, @agent_b_id)}
              state={@agent_b_state}
              events={@events_b}
            />
          </div>
        <% else %>
          <%!-- Empty state --%>
          <div class="card bg-base-200 border-2 border-base-300">
            <div class="card-body">
              <div class="text-center py-16">
                <div class="relative inline-block mb-4">
                  <.icon name="hero-arrows-right-left" class="size-16 text-base-content/20" />
                </div>
                <p class="text-base-content/50 text-lg font-terminal">
                  Select two agents to begin observation
                </p>
                <p class="text-base-content/30 text-sm mt-2 font-terminal">
                  Start agents at /substrate first, then compare their trajectories here
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
  # Components
  # ============================================================================

  attr(:label, :string, required: true)
  attr(:color, :string, required: true)
  attr(:agent_name, :string, required: true)
  attr(:state, :any, required: true)
  attr(:events, :list, required: true)

  defp agent_panel(assigns) do
    ~H"""
    <div class="space-y-4">
      <%!-- Panel Header --%>
      <div class={[
        "flex items-center gap-2 font-terminal text-sm uppercase border-b-2 pb-2",
        panel_border_class(@color)
      ]}>
        <span class={[
          "size-6 rounded flex items-center justify-center text-xs font-black",
          panel_badge_class(@color)
        ]}>
          {@label}
        </span>
        <span class={panel_text_class(@color)}>{@agent_name}</span>
        <span class={[
          "ml-auto size-2 rounded-full",
          if(@state, do: "bg-success animate-pulse", else: "bg-error")
        ]}>
        </span>
      </div>

      <%= if @state do %>
        <%!-- Stats --%>
        <div class={[
          "card bg-base-200 border-2 hover:border-opacity-80 transition-colors",
          panel_card_border(@color)
        ]}>
          <div class="card-body p-0">
            <div class={[
              "px-4 py-3 border-b-2 bg-base-300",
              panel_header_border(@color)
            ]}>
              <h2 class="card-title text-sm font-terminal uppercase gap-2">
                <.icon name="hero-cpu-chip" class={["size-4", panel_text_class(@color)]} />
                Substrate State
              </h2>
            </div>

            <div class="p-4">
              <div class="stats stats-vertical sm:stats-horizontal bg-base-300 w-full border border-base-content/10">
                <div class="stat">
                  <div class={["stat-figure", panel_text_class(@color)]}>
                    <.icon name="hero-arrow-path" class="size-6 neural-pulse" />
                  </div>
                  <div class="stat-title font-terminal uppercase text-xs">Tick</div>
                  <div class={["stat-value font-terminal", panel_text_class(@color)]}>
                    {@state.tick_count}
                  </div>
                  <div class="stat-desc font-terminal">
                    <%= if @state.last_tick_at do %>
                      {format_time(@state.last_tick_at)}
                    <% else %>
                      Awaiting first tick
                    <% end %>
                  </div>
                </div>

                <div class="stat">
                  <div class="stat-figure text-warning">
                    <.icon name="hero-inbox-stack" class="size-6" />
                  </div>
                  <div class="stat-title font-terminal uppercase text-xs">Pending</div>
                  <div class="stat-value text-warning font-terminal">
                    {length(@state.pending_events)}
                  </div>
                  <div class="stat-desc font-terminal">Events queued</div>
                </div>

                <div class="stat">
                  <div class="stat-title font-terminal uppercase text-xs">Interval</div>
                  <div class="stat-value font-terminal text-base-content/70 text-lg">
                    {div(@state.tick_interval, 1000)}s
                  </div>
                  <div class="stat-desc font-terminal">Tick freq</div>
                </div>
              </div>

              <%!-- Current Focus --%>
              <div class={[
                "mt-4 p-3 bg-base-300 border",
                panel_focus_border(@color)
              ]}>
                <div class="flex items-center gap-2 mb-2">
                  <span class="node-indicator active"></span>
                  <span class="text-xs font-terminal uppercase text-base-content/60">
                    Current Focus
                  </span>
                </div>
                <%= if @state.current_focus do %>
                  <p class={["text-sm font-terminal leading-relaxed", panel_text_class(@color)]}>
                    {@state.current_focus.statement}
                  </p>
                  <div class="flex items-center gap-2 mt-2">
                    <span class={["badge badge-xs font-terminal", panel_badge_sm(@color)]}>
                      {Float.round(@state.current_focus.confidence * 100, 0)}%
                    </span>
                    <span class="text-[10px] font-terminal text-base-content/40">
                      E:{@state.current_focus.entrenchment}
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

        <%!-- Event Stream --%>
        <div class={[
          "card bg-base-200 border-2 hover:border-opacity-80 transition-colors",
          panel_card_border(@color)
        ]}>
          <div class="card-body p-0">
            <div class={[
              "px-4 py-3 border-b-2 bg-base-300",
              panel_header_border(@color)
            ]}>
              <h2 class="card-title text-sm font-terminal uppercase gap-2">
                <.icon name="hero-signal" class={["size-4", panel_text_class(@color)]} /> Event Stream
                <span class="ml-auto text-[10px] text-base-content/40 font-terminal normal-case">
                  {length(@events)} events
                </span>
              </h2>
            </div>
            <div class="p-3 max-h-72 overflow-y-auto">
              <%= if @events == [] do %>
                <div class="flex flex-col items-center justify-center py-8 text-base-content/40">
                  <.icon name="hero-signal" class="size-6 mb-2" />
                  <p class="text-xs font-terminal">Waiting for events...</p>
                </div>
              <% else %>
                <ul class="space-y-1">
                  <li :for={event <- @events}>
                    <.compare_event_entry event={event} color={@color} />
                  </li>
                </ul>
              <% end %>
            </div>
          </div>
        </div>
      <% else %>
        <div class="card bg-base-200 border-2 border-base-300">
          <div class="card-body">
            <div class="text-center py-12">
              <.icon name="hero-cpu-chip" class="size-10 text-base-content/20 mb-2" />
              <p class="text-base-content/40 text-sm font-terminal">
                Substrate not running
              </p>
              <p class="text-base-content/30 text-xs mt-1 font-terminal">
                Start this agent at /substrate
              </p>
            </div>
          </div>
        </div>
      <% end %>
    </div>
    """
  end

  attr(:focus_a, :any, required: true)
  attr(:focus_b, :any, required: true)

  defp divergence_bar(assigns) do
    diverged? = focuses_diverged?(assigns.focus_a, assigns.focus_b)
    assigns = assign(assigns, :diverged?, diverged?)

    ~H"""
    <div class={[
      "flex items-center gap-3 px-4 py-2 border-2 font-terminal text-xs uppercase transition-all duration-300",
      if(@diverged?,
        do: "bg-error/10 border-error/40 text-error",
        else: "bg-success/10 border-success/40 text-success"
      )
    ]}>
      <span class={[
        "size-2 rounded-full",
        if(@diverged?, do: "bg-error animate-pulse", else: "bg-success")
      ]}>
      </span>
      <%= if @diverged? do %>
        <span>Diverged — agents focusing on different beliefs</span>
      <% else %>
        <span>Converged — agents share the same focus</span>
      <% end %>
      <div class="flex-1"></div>
      <span class="text-[10px] text-base-content/40 normal-case">
        Focus comparison
      </span>
    </div>
    """
  end

  attr(:event, :map, required: true)
  attr(:color, :string, required: true)

  defp compare_event_entry(assigns) do
    ~H"""
    <div class={[
      "flex items-start gap-2 p-2 border transition-colors",
      event_style(@event.type, @color)
    ]}>
      <div class="mt-0.5">
        <%= case @event.type do %>
          <% :tick -> %>
            <.icon name="hero-arrow-path" class={["size-3.5", panel_text_class(@color) <> "/70"]} />
          <% :driver_action -> %>
            <.icon name="hero-play" class="size-3.5 text-info/70" />
          <% _ -> %>
            <.icon name="hero-signal" class="size-3.5 text-base-content/40" />
        <% end %>
      </div>
      <div class="flex-1 min-w-0">
        <%= case @event.type do %>
          <% :tick -> %>
            <p class="text-xs font-terminal">
              <span class={panel_text_class(@color)}>Tick {@event.tick_count}</span>
              <%= if @event.focus do %>
                <span class="text-base-content/50"> — </span>
                <span class="text-base-content/60 line-clamp-1">{truncate(@event.focus, 50)}</span>
              <% end %>
            </p>
          <% :driver_action -> %>
            <p class="text-xs font-terminal">
              <span class="text-info">Action</span>
              <span class="text-base-content/60">{inspect(@event.action)}</span>
            </p>
          <% _ -> %>
            <p class="text-xs font-terminal text-base-content/50">Event</p>
        <% end %>
        <span class="text-[10px] font-terminal text-base-content/30 block mt-0.5">
          {format_time(@event.time)}
        </span>
      </div>
    </div>
    """
  end

  # ============================================================================
  # Color Helpers — panel theming
  # ============================================================================

  defp panel_text_class("primary"), do: "text-primary"
  defp panel_text_class("secondary"), do: "text-secondary"
  defp panel_text_class(_), do: "text-base-content"

  defp panel_border_class("primary"), do: "border-primary/30"
  defp panel_border_class("secondary"), do: "border-secondary/30"
  defp panel_border_class(_), do: "border-base-content/20"

  defp panel_card_border("primary"), do: "border-primary/50"
  defp panel_card_border("secondary"), do: "border-secondary/50"
  defp panel_card_border(_), do: "border-base-content/20"

  defp panel_header_border("primary"), do: "border-primary/30"
  defp panel_header_border("secondary"), do: "border-secondary/30"
  defp panel_header_border(_), do: "border-base-content/10"

  defp panel_focus_border("primary"), do: "border-accent/30"
  defp panel_focus_border("secondary"), do: "border-accent/30"
  defp panel_focus_border(_), do: "border-base-content/20"

  defp panel_badge_class("primary"), do: "bg-primary/20 text-primary"
  defp panel_badge_class("secondary"), do: "bg-secondary/20 text-secondary"
  defp panel_badge_class(_), do: "bg-base-300 text-base-content"

  defp panel_badge_sm("primary"), do: "badge-primary"
  defp panel_badge_sm("secondary"), do: "badge-secondary"
  defp panel_badge_sm(_), do: "badge-ghost"

  defp event_style(:tick, "primary"),
    do: "bg-base-300/50 border-primary/10 hover:border-primary/30"

  defp event_style(:tick, "secondary"),
    do: "bg-base-300/50 border-secondary/10 hover:border-secondary/30"

  defp event_style(:driver_action, _), do: "bg-base-300/50 border-info/10 hover:border-info/30"
  defp event_style(_, _), do: "bg-base-300/50 border-base-content/5"

  # ============================================================================
  # Helpers
  # ============================================================================

  defp fetch_state(nil), do: nil

  defp fetch_state(agent_id) do
    case Substrate.get_agent_state(agent_id) do
      {:ok, state} -> state
      {:error, _} -> nil
    end
  end

  defp unsubscribe_agent(nil), do: :ok

  defp unsubscribe_agent(agent_id) do
    Phoenix.PubSub.unsubscribe(Lincoln.PubSub, PubSubBroadcaster.substrate_topic(agent_id))
    Phoenix.PubSub.unsubscribe(Lincoln.PubSub, PubSubBroadcaster.driver_topic(agent_id))
  end

  defp get_agent_name(agents, id) do
    case Enum.find(agents, fn a -> a.id == id end) do
      nil -> "Unknown"
      agent -> agent.name
    end
  end

  defp focus_label(nil), do: nil
  defp focus_label(%{statement: s}), do: s
  defp focus_label(_), do: nil

  defp focuses_diverged?(nil, nil), do: false
  defp focuses_diverged?(nil, _), do: true
  defp focuses_diverged?(_, nil), do: true

  defp focuses_diverged?(a, b) do
    a_statement = Map.get(a, :statement, nil) || Map.get(a, "statement", nil)
    b_statement = Map.get(b, :statement, nil) || Map.get(b, "statement", nil)
    a_statement != b_statement
  end

  defp prepend_event(events, event) do
    [event | events] |> Enum.take(@max_events)
  end

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
