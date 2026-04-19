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
      |> assign(:scoring_a, nil)
      |> assign(:scoring_b, nil)

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
      Phoenix.PubSub.subscribe(Lincoln.PubSub, PubSubBroadcaster.substrate_topic(b_id))
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

  # Handle enriched tick with scoring detail
  @impl true
  def handle_info({:tick, tick_count, current_focus, scoring_detail}, socket) do
    prev_a = socket.assigns.agent_a_state
    prev_b = socket.assigns.agent_b_state
    new_a = fetch_state(socket.assigns.agent_a_id) || prev_a
    new_b = fetch_state(socket.assigns.agent_b_id) || prev_b

    {events_a, scoring_a} =
      case build_agent_tick_event(new_a, prev_a, tick_count, current_focus) do
        nil -> {socket.assigns.events_a, socket.assigns.scoring_a}
        event -> {prepend_event(socket.assigns.events_a, event), scoring_detail}
      end

    {events_b, scoring_b} =
      case build_agent_tick_event(new_b, prev_b, tick_count, current_focus) do
        nil -> {socket.assigns.events_b, socket.assigns.scoring_b}
        event -> {prepend_event(socket.assigns.events_b, event), scoring_detail}
      end

    {:noreply,
     socket
     |> assign(:agent_a_state, new_a)
     |> assign(:agent_b_state, new_b)
     |> assign(:events_a, events_a)
     |> assign(:events_b, events_b)
     |> assign(:scoring_a, scoring_a)
     |> assign(:scoring_b, scoring_b)}
  end

  # Backward compat for old-format tick without scoring detail
  def handle_info({:tick, tick_count, current_focus}, socket) do
    handle_info({:tick, tick_count, current_focus, nil}, socket)
  end

  # Handle idle ticks — substrate is thinking quietly
  def handle_info({:idle_tick, _tick_count, _idle_streak, _belief}, socket) do
    # Refresh states to stay in sync during idle periods
    new_a = fetch_state(socket.assigns.agent_a_id) || socket.assigns.agent_a_state
    new_b = fetch_state(socket.assigns.agent_b_id) || socket.assigns.agent_b_state

    {:noreply,
     socket
     |> assign(:agent_a_state, new_a)
     |> assign(:agent_b_state, new_b)}
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
        <%!-- Header --%>
        <.page_header
          title="Divergence Observatory"
          subtitle="Watch two cognitive substrates diverge on identical inputs"
          icon="hero-arrows-right-left"
          icon_color="text-primary"
        >
          <:actions>
            <.link
              navigate={~p"/substrate"}
              class="btn btn-sm bg-base-300 border-2 border-base-content/20 font-terminal text-xs uppercase shadow-brutal-sm"
            >
              <.icon name="hero-cpu-chip" class="size-3.5" /> Single View
            </.link>
          </:actions>
        </.page_header>

        <%!-- Agent Selector --%>
        <.card variant={:primary}>
          <.form for={to_form(%{}, as: :agents)} phx-submit="select_agents" id="agent-selector">
            <div class="flex items-end gap-4">
              <div class="flex-1">
                <label class="text-[10px] font-terminal uppercase tracking-widest text-base-content/40 mb-1 block">
                  Agent A
                </label>
                <select
                  name="agent_a"
                  class="select select-bordered w-full bg-base-300 border-2 border-primary/20 font-terminal text-sm focus:border-primary focus:outline-none"
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
                <label class="text-[10px] font-terminal uppercase tracking-widest text-base-content/40 mb-1 block">
                  Agent B
                </label>
                <select
                  name="agent_b"
                  class="select select-bordered w-full bg-base-300 border-2 border-secondary/20 font-terminal text-sm focus:border-secondary focus:outline-none"
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
                class="btn bg-primary/20 border-2 border-primary/50 hover:bg-primary/30 text-primary font-terminal uppercase text-xs shadow-brutal-sm"
              >
                <.icon name="hero-eye" class="size-4" /> Observe
              </button>
            </div>
          </.form>
        </.card>

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
              scoring={@scoring_a}
            />

            <%!-- Agent B --%>
            <.agent_panel
              label="B"
              color="secondary"
              agent_name={get_agent_name(@agents, @agent_b_id)}
              state={@agent_b_state}
              events={@events_b}
              scoring={@scoring_b}
            />
          </div>
        <% else %>
          <%!-- Empty state --%>
          <.card>
            <.empty_state
              icon="hero-arrows-right-left"
              title="Select two agents to begin observation"
              description="Start agents at /substrate first, then compare their trajectories here"
            />
          </.card>
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
  attr(:scoring, :any, default: nil)

  defp agent_panel(assigns) do
    ~H"""
    <div class="space-y-4">
      <%!-- Panel Header --%>
      <div class={[
        "flex items-center gap-2 font-terminal text-sm uppercase border-b-2 pb-2",
        panel_border_class(@color)
      ]}>
        <.badge type={panel_badge_type(@color)}>{@label}</.badge>
        <span class={panel_text_class(@color)}>{@agent_name}</span>
        <span class="ml-auto">
          <.status_indicator
            status={if(@state, do: :online, else: :offline)}
            pulse={@state != nil}
            size={:sm}
          />
        </span>
      </div>

      <%= if @state do %>
        <%!-- Stats --%>
        <.card variant={panel_variant(@color)} class="shadow-brutal">
          <:header>
            <div class="flex items-center gap-2">
              <.icon name="hero-cpu-chip" class={["size-4", panel_text_class(@color)]} />
              <span>Substrate State</span>
            </div>
          </:header>
          <div class="stats stats-vertical sm:stats-horizontal bg-base-300 w-full border-2 border-base-content/10">
            <div class="stat">
              <div class={["stat-figure", panel_text_class(@color)]}>
                <.icon name="hero-arrow-path" class="size-6 neural-pulse" />
              </div>
              <div class="text-[10px] font-terminal uppercase tracking-widest text-base-content/40">
                Tick
              </div>
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
              <div class="text-[10px] font-terminal uppercase tracking-widest text-base-content/40">
                Pending
              </div>
              <div class="stat-value text-warning font-terminal">
                {length(@state.pending_events)}
              </div>
              <div class="stat-desc font-terminal">Events queued</div>
            </div>

            <div class="stat">
              <div class="text-[10px] font-terminal uppercase tracking-widest text-base-content/40">
                Mode
              </div>
              <div class="stat-value font-terminal text-base-content/70 text-lg">
                {if Map.get(@state, :idle_streak, 0) > 0, do: "idle", else: "active"}
              </div>
              <div class="stat-desc font-terminal">Event-driven</div>
            </div>
          </div>

          <%!-- Current Focus --%>
          <div class={[
            "mt-4 p-3 bg-base-300 border-2",
            panel_focus_border(@color)
          ]}>
            <div class="flex items-center gap-2 mb-2">
              <.status_indicator status={:online} pulse size={:sm} />
              <span class="text-[10px] font-terminal uppercase tracking-widest text-base-content/40">
                Current Focus
              </span>
            </div>
            <%= if @state.current_focus do %>
              <p class={["text-sm font-terminal leading-relaxed", panel_text_class(@color)]}>
                {@state.current_focus.statement}
              </p>
              <div class="flex items-center gap-2 mt-2">
                <.badge type={panel_badge_type(@color)}>
                  {Float.round(@state.current_focus.confidence * 100, 0)}%
                </.badge>
                <span class="text-[10px] font-terminal uppercase tracking-widest text-base-content/40">
                  E:{@state.current_focus.entrenchment}
                </span>
              </div>
            <% else %>
              <p class="text-sm font-terminal text-base-content/40 italic">
                Idle — no belief in focus
              </p>
            <% end %>
          </div>
        </.card>

        <%!-- Scoring Breakdown --%>
        <%= if @scoring do %>
          <.scoring_breakdown scoring={@scoring} color={@color} />
        <% end %>

        <%!-- Event Stream --%>
        <.card variant={panel_variant(@color)} class="shadow-brutal">
          <:header>
            <div class="flex items-center gap-2 flex-1">
              <.icon name="hero-signal" class={["size-4", panel_text_class(@color)]} />
              <span>Event Stream</span>
              <span class="ml-auto text-[10px] text-base-content/40 font-terminal normal-case">
                {length(@events)} events
              </span>
            </div>
          </:header>
          <div class="-m-4 p-3 max-h-80 overflow-y-auto">
            <%= if @events == [] do %>
              <.empty_state icon="hero-signal" title="Waiting for events..." />
            <% else %>
              <ul class="space-y-1">
                <li :for={event <- @events}>
                  <.compare_event_entry event={event} color={@color} />
                </li>
              </ul>
            <% end %>
          </div>
        </.card>
      <% else %>
        <.card>
          <.empty_state
            icon="hero-cpu-chip"
            title="Substrate not running"
            description="Start this agent at /substrate"
          />
        </.card>
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
      "flex items-center gap-3 px-4 py-2 border-2 font-terminal text-xs uppercase transition-all duration-300 shadow-brutal-sm",
      if(@diverged?,
        do: "bg-error/10 border-error/40 text-error",
        else: "bg-success/10 border-success/40 text-success"
      )
    ]}>
      <.status_indicator
        status={if(@diverged?, do: :error, else: :online)}
        pulse={@diverged?}
        size={:sm}
      />
      <%= if @diverged? do %>
        <span>Diverged — agents focusing on different beliefs</span>
      <% else %>
        <span>Converged — agents share the same focus</span>
      <% end %>
      <div class="flex-1"></div>
      <span class="text-[10px] font-terminal uppercase tracking-widest text-base-content/40 normal-case">
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
      "flex items-start gap-2 p-2 border-2 transition-colors",
      event_style(@event.type, @color)
    ]}>
      <div class="mt-0.5">
        <%= case @event.type do %>
          <% :tick -> %>
            <.icon name="hero-arrow-path" class={["size-3.5", panel_text_class(@color) <> "/70"]} />
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

  attr(:scoring, :map, required: true)
  attr(:color, :string, required: true)

  defp scoring_breakdown(assigns) do
    candidates = Map.get(assigns.scoring, :top_candidates, [])
    candidate_count = Map.get(assigns.scoring, :candidate_count, 0)
    assigns = assign(assigns, :candidates, candidates)
    assigns = assign(assigns, :candidate_count, candidate_count)

    ~H"""
    <.card variant={panel_variant(@color)} class="shadow-brutal">
      <:header>
        <div class="flex items-center gap-2 flex-1">
          <.icon name="hero-chart-bar" class={["size-4", panel_text_class(@color)]} />
          <span>Attention Scoring</span>
          <span class="ml-auto text-[10px] text-base-content/40 font-terminal normal-case">
            {@candidate_count} beliefs scored
          </span>
        </div>
      </:header>
      <div class="space-y-2">
        <%= for candidate <- @candidates do %>
          <div class={[
            "p-2 border-2 bg-base-300/50 space-y-1",
            if(candidate.rank == 1,
              do: panel_focus_border(@color),
              else: "border-base-content/5"
            )
          ]}>
            <div class="flex items-center gap-2">
              <.badge type={if(candidate.rank == 1, do: panel_badge_type(@color), else: :default)}>
                #{candidate.rank}
              </.badge>
              <span class="text-xs font-terminal text-base-content/70 flex-1 line-clamp-1">
                {candidate.statement}
              </span>
              <span class={[
                "text-xs font-terminal font-bold",
                panel_text_class(@color)
              ]}>
                {format_score(candidate.components.final_score)}
              </span>
            </div>
            <div class="flex gap-1 ml-6">
              <.score_bar label="N" value={candidate.components.novelty} color="info" />
              <.score_bar label="T" value={candidate.components.tension} color="warning" />
              <.score_bar label="S" value={candidate.components.staleness} color="error" />
              <.score_bar label="D" value={candidate.components.depth} color="success" />
              <%= if candidate.components.focus_boost > 0 do %>
                <.badge type={:accent} class="ml-1">
                  +{format_score(candidate.components.focus_boost)} focus
                </.badge>
              <% end %>
            </div>
          </div>
        <% end %>
      </div>
    </.card>
    """
  end

  attr(:label, :string, required: true)
  attr(:value, :float, required: true)
  attr(:color, :string, required: true)

  defp score_bar(assigns) do
    width = Float.round(assigns.value * 100, 0)
    assigns = assign(assigns, :width, width)

    ~H"""
    <div class="flex items-center gap-0.5" title={"#{@label}: #{format_score(@value)}"}>
      <span class="text-[8px] font-terminal text-base-content/40 w-2">{@label}</span>
      <div class="w-8 h-1.5 bg-base-100 border border-base-content/10 overflow-hidden">
        <div
          class={["h-full rounded-full", bar_color(@color)]}
          style={"width: #{@width}%"}
        >
        </div>
      </div>
    </div>
    """
  end

  defp bar_color("info"), do: "bg-info"
  defp bar_color("warning"), do: "bg-warning"
  defp bar_color("error"), do: "bg-error"
  defp bar_color("success"), do: "bg-success"
  defp bar_color(_), do: "bg-base-content/50"

  defp format_score(score) when is_float(score), do: :erlang.float_to_binary(score, decimals: 2)
  defp format_score(_), do: "—"

  # ============================================================================
  # Color Helpers — panel theming
  # ============================================================================

  defp panel_variant("primary"), do: :primary
  defp panel_variant("secondary"), do: :secondary
  defp panel_variant(_), do: :default

  defp panel_badge_type("primary"), do: :primary
  defp panel_badge_type("secondary"), do: :secondary
  defp panel_badge_type(_), do: :default

  defp panel_text_class("primary"), do: "text-primary"
  defp panel_text_class("secondary"), do: "text-secondary"
  defp panel_text_class(_), do: "text-base-content"

  defp panel_border_class("primary"), do: "border-primary/30"
  defp panel_border_class("secondary"), do: "border-secondary/30"
  defp panel_border_class(_), do: "border-base-content/20"

  defp panel_focus_border("primary"), do: "border-accent/30"
  defp panel_focus_border("secondary"), do: "border-accent/30"
  defp panel_focus_border(_), do: "border-base-content/20"

  defp event_style(:tick, "primary"),
    do: "bg-base-300/50 border-primary/10 hover:border-primary/30"

  defp event_style(:tick, "secondary"),
    do: "bg-base-300/50 border-secondary/10 hover:border-secondary/30"

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
  end

  defp get_agent_name(agents, id) do
    case Enum.find(agents, fn a -> a.id == id end) do
      nil -> "Unknown"
      agent -> agent.name
    end
  end

  defp build_agent_tick_event(nil, _prev, _tick, _focus), do: nil

  defp build_agent_tick_event(new_state, nil, fallback_tick, fallback_focus)
       when new_state != nil do
    %{
      time: DateTime.utc_now(),
      type: :tick,
      tick_count: fallback_tick,
      focus: focus_label(fallback_focus)
    }
  end

  defp build_agent_tick_event(new_state, prev_state, _tick, _focus)
       when new_state.tick_count != prev_state.tick_count do
    %{
      time: DateTime.utc_now(),
      type: :tick,
      tick_count: new_state.tick_count,
      focus: focus_label(new_state.current_focus)
    }
  end

  defp build_agent_tick_event(_new, _prev, _tick, _focus), do: nil

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
