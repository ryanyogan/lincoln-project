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
  alias Lincoln.Substrate.AttentionParams

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
      |> assign(:attention_params_form, build_params_form(agent))
      |> assign(:top_beliefs, [])
      |> assign(:tier_counts, %{local: 0, ollama: 0, claude: 0})
      |> assign(:recent_contradictions, [])
      |> assign(:recent_cascades, [])
      |> assign(:self_model, Lincoln.SelfModel.get(agent.id))

    if connected?(socket) do
      Phoenix.PubSub.subscribe(Lincoln.PubSub, PubSubBroadcaster.substrate_topic(agent.id))
      Phoenix.PubSub.subscribe(Lincoln.PubSub, PubSubBroadcaster.driver_topic(agent.id))
      Phoenix.PubSub.subscribe(Lincoln.PubSub, PubSubBroadcaster.attention_topic(agent.id))
      Phoenix.PubSub.subscribe(Lincoln.PubSub, PubSubBroadcaster.skeptic_topic(agent.id))
      Phoenix.PubSub.subscribe(Lincoln.PubSub, PubSubBroadcaster.resonator_topic(agent.id))
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

    tier_counts =
      case action do
        %{tier: tier} when tier in [:local, :ollama, :claude] ->
          Map.update!(socket.assigns.tier_counts, tier, &(&1 + 1))

        _ ->
          socket.assigns.tier_counts
      end

    {:noreply,
     socket
     |> assign(:recent_events, recent)
     |> assign(:tier_counts, tier_counts)}
  end

  def handle_info({:next_thought, belief, score}, socket) do
    top_beliefs = update_top_beliefs(socket.assigns.top_beliefs, belief, score)
    {:noreply, assign(socket, :top_beliefs, top_beliefs)}
  end

  def handle_info({:contradiction_detected, relationship, source_belief, target_belief}, socket) do
    entry = %{
      relationship: relationship,
      source: source_belief,
      target: target_belief,
      detected_at: DateTime.utc_now()
    }

    contradictions = [entry | socket.assigns.recent_contradictions] |> Enum.take(10)
    {:noreply, assign(socket, :recent_contradictions, contradictions)}
  end

  def handle_info({:cascade_detected, cascade_info}, socket) do
    entry = Map.put(cascade_info, :detected_at, DateTime.utc_now())
    cascades = [entry | socket.assigns.recent_cascades] |> Enum.take(10)
    {:noreply, assign(socket, :recent_cascades, cascades)}
  end

  # Catch-all for other PubSub messages
  def handle_info(_msg, socket), do: {:noreply, socket}

  # ============================================================================
  # Events
  # ============================================================================

  @impl true
  def handle_event("select_preset", %{"preset" => preset}, socket) do
    params =
      case preset do
        "focused" -> AttentionParams.focused()
        "butterfly" -> AttentionParams.butterfly()
        "adhd_like" -> AttentionParams.adhd_like()
        _ -> AttentionParams.default()
      end

    form_params = Map.new(params, fn {k, v} -> {to_string(k), to_string(v)} end)

    {:noreply,
     assign(socket, :attention_params_form, to_form(form_params, as: :attention_params))}
  end

  def handle_event("apply_params", %{"attention_params" => raw_params}, socket) do
    parsed = %{
      novelty_weight: parse_float(raw_params["novelty_weight"], 0.3),
      focus_momentum: parse_float(raw_params["focus_momentum"], 0.5),
      interrupt_threshold: parse_float(raw_params["interrupt_threshold"], 0.7),
      boredom_decay: parse_float(raw_params["boredom_decay"], 0.1),
      depth_preference: parse_float(raw_params["depth_preference"], 0.5),
      tick_interval_ms: parse_integer(raw_params["tick_interval_ms"], 5_000)
    }

    {:ok, _agent} = Agents.update_agent(socket.assigns.agent, %{attention_params: parsed})

    case Substrate.get_process(socket.assigns.agent.id, :attention) do
      {:ok, pid} -> GenServer.cast(pid, {:reload_params})
      _ -> :ok
    end

    {:noreply, put_flash(socket, :info, "Attention parameters updated")}
  end

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
                        <span class="text-xs font-terminal uppercase text-base-content/60">
                          Current Focus
                        </span>
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

              <%!-- Self Model Card --%>
              <div class="card bg-base-200/50 border border-base-content/10">
                <div class="card-body p-4">
                  <h3 class="font-terminal text-sm text-base-content/50 mb-2">SELF MODEL</h3>
                  <%= if @self_model do %>
                    <p class="text-xs text-base-content/60">
                      {Lincoln.SelfModel.to_summary_string(@self_model)}
                    </p>
                    <div class="flex gap-3 mt-2 text-xs font-terminal text-base-content/30">
                      <span>L0:{@self_model.local_tier_count}</span>
                      <span>L1:{@self_model.ollama_tier_count}</span>
                      <span>L2:{@self_model.claude_tier_count}</span>
                    </div>
                  <% else %>
                    <p class="text-xs text-base-content/30">Updates every 50 ticks</p>
                  <% end %>
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

              <%!-- Attention Parameters Card --%>
              <div class="card bg-base-200 border-2 border-warning/50 hover:border-warning transition-colors">
                <div class="card-body p-0">
                  <div class="flex items-center justify-between px-4 py-3 border-b-2 border-warning/30 bg-base-300">
                    <h2 class="card-title text-sm font-terminal uppercase gap-2">
                      <.icon name="hero-adjustments-horizontal" class="size-4 text-warning" />
                      Attention Parameters
                    </h2>
                  </div>
                  <div class="p-4">
                    <div class="flex flex-wrap gap-1.5 mb-4">
                      <button
                        phx-click="select_preset"
                        phx-value-preset="focused"
                        class="btn btn-xs bg-base-300 border-warning/30 hover:border-warning text-warning font-terminal uppercase"
                      >
                        Focused
                      </button>
                      <button
                        phx-click="select_preset"
                        phx-value-preset="butterfly"
                        class="btn btn-xs bg-base-300 border-warning/30 hover:border-warning text-warning font-terminal uppercase"
                      >
                        Butterfly
                      </button>
                      <button
                        phx-click="select_preset"
                        phx-value-preset="adhd_like"
                        class="btn btn-xs bg-base-300 border-warning/30 hover:border-warning text-warning font-terminal uppercase"
                      >
                        ADHD-like
                      </button>
                      <button
                        phx-click="select_preset"
                        phx-value-preset="default"
                        class="btn btn-xs bg-base-300 border-base-content/10 hover:border-base-content/30 text-base-content/60 font-terminal uppercase"
                      >
                        Default
                      </button>
                    </div>

                    <.form
                      for={@attention_params_form}
                      phx-submit="apply_params"
                      id="attention-params-form"
                    >
                      <div class="grid grid-cols-2 gap-3">
                        <.input
                          field={@attention_params_form[:novelty_weight]}
                          type="number"
                          label="novelty_weight"
                          step="0.05"
                          min="0"
                          max="1"
                          class="w-full input input-xs bg-base-300 border-base-content/10 font-terminal text-xs"
                        />
                        <.input
                          field={@attention_params_form[:focus_momentum]}
                          type="number"
                          label="focus_momentum"
                          step="0.05"
                          min="0"
                          max="1"
                          class="w-full input input-xs bg-base-300 border-base-content/10 font-terminal text-xs"
                        />
                        <.input
                          field={@attention_params_form[:interrupt_threshold]}
                          type="number"
                          label="interrupt_threshold"
                          step="0.05"
                          min="0"
                          max="1"
                          class="w-full input input-xs bg-base-300 border-base-content/10 font-terminal text-xs"
                        />
                        <.input
                          field={@attention_params_form[:boredom_decay]}
                          type="number"
                          label="boredom_decay"
                          step="0.05"
                          min="0"
                          max="1"
                          class="w-full input input-xs bg-base-300 border-base-content/10 font-terminal text-xs"
                        />
                        <.input
                          field={@attention_params_form[:depth_preference]}
                          type="number"
                          label="depth_preference"
                          step="0.05"
                          min="0"
                          max="1"
                          class="w-full input input-xs bg-base-300 border-base-content/10 font-terminal text-xs"
                        />
                        <.input
                          field={@attention_params_form[:tick_interval_ms]}
                          type="number"
                          label="tick_interval_ms"
                          step="1000"
                          min="1000"
                          max="60000"
                          class="w-full input input-xs bg-base-300 border-base-content/10 font-terminal text-xs"
                        />
                      </div>
                      <button
                        type="submit"
                        class="btn btn-sm bg-warning/20 border-warning/50 hover:bg-warning/30 text-warning font-terminal uppercase w-full mt-4"
                      >
                        <.icon name="hero-check" class="size-3.5" /> Apply Parameters
                      </button>
                    </.form>
                  </div>
                </div>
              </div>
            </div>

            <%!-- Right column: Event Timeline + Beliefs + Tiers (1/3 width) --%>
            <div class="lg:col-span-1 space-y-6">
              <div class="card bg-base-200 border-2 border-secondary/50 hover:border-secondary transition-colors">
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

              <%!-- Belief Score Ranking --%>
              <div class="card bg-base-200 border-2 border-accent/50 hover:border-accent transition-colors">
                <div class="card-body p-0">
                  <div class="px-4 py-3 border-b-2 border-accent/30 bg-base-300">
                    <h2 class="card-title text-sm font-terminal uppercase gap-2">
                      <.icon name="hero-chart-bar" class="size-4 text-accent" /> Top Scored Beliefs
                    </h2>
                  </div>
                  <div class="p-3">
                    <%= if @top_beliefs == [] do %>
                      <div class="flex flex-col items-center justify-center py-8 text-base-content/40">
                        <.icon name="hero-chart-bar" class="size-6 mb-2" />
                        <p class="text-xs font-terminal">No scored beliefs yet</p>
                      </div>
                    <% else %>
                      <ul class="space-y-2">
                        <li
                          :for={{belief, score} <- @top_beliefs}
                          class="p-2 bg-base-300 border border-accent/10 hover:border-accent/30 transition-colors"
                        >
                          <div class="flex items-center justify-between mb-1">
                            <span class="text-xs font-terminal font-bold text-accent">
                              {Float.round(score * 100, 1)}
                            </span>
                            <span class="badge badge-xs bg-accent/20 text-accent border-accent/30 font-terminal">
                              E:{belief.entrenchment}
                            </span>
                          </div>
                          <p class="text-xs font-terminal text-base-content/70 leading-relaxed line-clamp-2">
                            {belief.statement}
                          </p>
                          <div class="flex items-center gap-2 mt-1">
                            <span class="text-[10px] font-terminal text-base-content/40">
                              C:{Float.round(belief.confidence * 100, 0)}%
                            </span>
                          </div>
                        </li>
                      </ul>
                    <% end %>
                  </div>
                </div>
              </div>

              <%!-- Tier Distribution --%>
              <div class="card bg-base-200 border-2 border-base-content/20 hover:border-base-content/30 transition-colors">
                <div class="card-body p-0">
                  <div class="px-4 py-3 border-b-2 border-base-content/10 bg-base-300">
                    <h2 class="card-title text-sm font-terminal uppercase gap-2">
                      <.icon name="hero-server-stack" class="size-4 text-base-content/60" />
                      Tier Distribution
                    </h2>
                  </div>
                  <div class="p-4">
                    <div class="grid grid-cols-3 gap-3">
                      <.tier_counter label="Local" count={@tier_counts.local} color="success" />
                      <.tier_counter label="Ollama" count={@tier_counts.ollama} color="warning" />
                      <.tier_counter label="Claude" count={@tier_counts.claude} color="error" />
                    </div>
                    <div class="mt-3 pt-3 border-t border-base-content/10">
                      <div class="flex items-center justify-between text-xs font-terminal text-base-content/50">
                        <span>Total</span>
                        <span class="font-bold text-base-content/70">
                          {@tier_counts.local + @tier_counts.ollama + @tier_counts.claude}
                        </span>
                      </div>
                    </div>
                  </div>
                </div>
              </div>

              <%!-- Skeptic Panel --%>
              <div class="card bg-base-200 border-2 border-error/50 hover:border-error transition-colors">
                <div class="card-body p-0">
                  <div class="px-4 py-3 border-b-2 border-error/30 bg-base-300">
                    <h2 class="card-title text-sm font-terminal uppercase gap-2">
                      <.icon name="hero-shield-exclamation" class="size-4 text-error" />
                      Skeptic — Contradictions
                    </h2>
                  </div>
                  <div class="p-3 max-h-[24rem] overflow-y-auto">
                    <%= if @recent_contradictions == [] do %>
                      <div class="flex flex-col items-center justify-center py-8 text-base-content/40">
                        <.icon name="hero-shield-exclamation" class="size-6 mb-2" />
                        <p class="text-xs font-terminal">No contradictions detected yet</p>
                      </div>
                    <% else %>
                      <div class="space-y-2">
                        <%= for entry <- @recent_contradictions do %>
                          <div class="p-2 bg-base-300 border border-error/10 hover:border-error/30 transition-colors">
                            <div class="text-[10px] text-error/70 font-terminal mb-1">
                              {format_time(entry.detected_at)} · confidence: {Float.round(
                                entry.relationship.confidence,
                                2
                              )}
                            </div>
                            <div class="text-xs font-terminal text-base-content/70 truncate">
                              {entry.source.statement}
                            </div>
                            <div class="text-[10px] text-error/40 text-center font-terminal my-0.5">
                              ↕ contradicts
                            </div>
                            <div class="text-xs font-terminal text-base-content/70 truncate">
                              {entry.target.statement}
                            </div>
                          </div>
                        <% end %>
                      </div>
                    <% end %>
                  </div>
                </div>
              </div>

              <%!-- Resonator Panel --%>
              <div class="card bg-base-200 border-2 border-success/50 hover:border-success transition-colors">
                <div class="card-body p-0">
                  <div class="px-4 py-3 border-b-2 border-success/30 bg-base-300">
                    <h2 class="card-title text-sm font-terminal uppercase gap-2">
                      <.icon name="hero-bolt" class="size-4 text-success" /> Resonator — Cascades
                    </h2>
                  </div>
                  <div class="p-3 max-h-[24rem] overflow-y-auto">
                    <%= if @recent_cascades == [] do %>
                      <div class="flex flex-col items-center justify-center py-8 text-base-content/40">
                        <.icon name="hero-bolt" class="size-6 mb-2" />
                        <p class="text-xs font-terminal">No cascades detected yet</p>
                      </div>
                    <% else %>
                      <div class="space-y-2">
                        <%= for cascade <- @recent_cascades do %>
                          <div class="p-2 bg-base-300 border border-success/10 hover:border-success/30 transition-colors">
                            <div class="text-[10px] text-success/70 font-terminal">
                              {format_time(cascade.detected_at)}
                            </div>
                            <div class="flex gap-3 text-xs font-terminal text-base-content/70 mt-1">
                              <span>cluster: {cascade.cluster_size} beliefs</span>
                              <span>score: {Float.round(cascade.cascade_score, 2)}</span>
                              <span>+{cascade.relationships_created} links</span>
                            </div>
                          </div>
                        <% end %>
                      </div>
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
          <span class="text-base-content/60">{inspect(@event.action)}</span>
        </p>
      <% _ -> %>
        <p class="text-xs font-terminal text-base-content/50">Unknown event</p>
    <% end %>
    """
  end

  attr(:label, :string, required: true)
  attr(:count, :integer, required: true)
  attr(:color, :string, required: true)

  defp tier_counter(assigns) do
    assigns = assign(assigns, :color_class, tier_color_class(assigns.color))

    ~H"""
    <div class="text-center p-2 bg-base-300 border border-base-content/10">
      <div class={["text-xl font-terminal font-black", @color_class]}>
        {@count}
      </div>
      <div class="text-[10px] font-terminal uppercase text-base-content/50 mt-0.5">
        {@label}
      </div>
    </div>
    """
  end

  defp tier_color_class("success"), do: "text-success"
  defp tier_color_class("warning"), do: "text-warning"
  defp tier_color_class("error"), do: "text-error"
  defp tier_color_class(_), do: "text-base-content"

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

  defp build_params_form(agent) do
    raw = agent.attention_params || %{}
    defaults = AttentionParams.default()

    string_params =
      Map.new(defaults, fn {key, default_val} ->
        str_key = to_string(key)
        val = raw[str_key] || raw[key] || default_val
        {str_key, to_string(val)}
      end)

    to_form(string_params, as: :attention_params)
  end

  defp update_top_beliefs(current, belief, score) do
    [{belief, score} | Enum.reject(current, fn {b, _} -> b.id == belief.id end)]
    |> Enum.sort_by(fn {_, s} -> s end, :desc)
    |> Enum.take(5)
  end

  defp parse_float(str, default) when is_binary(str) do
    case Float.parse(str) do
      {f, _} -> f
      :error -> default
    end
  end

  defp parse_float(_, default), do: default

  defp parse_integer(str, default) when is_binary(str) do
    case Integer.parse(str) do
      {i, _} -> i
      :error -> default
    end
  end

  defp parse_integer(_, default), do: default
end
