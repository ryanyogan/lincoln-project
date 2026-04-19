defmodule LincolnWeb.SubstrateThoughtsLive do
  @moduledoc """
  Live dashboard for the Thought Tree — watching thoughts spawn, execute,
  and terminate as real OTP processes in real time.

  Each row is a supervised process with its own lifecycle. This is the demo:
  someone watching it sees thoughts spawn, work, and die.
  """
  use LincolnWeb, :live_view

  alias Lincoln.{Agents, Substrate}
  alias Lincoln.PubSubBroadcaster
  alias Lincoln.Substrate.Thoughts

  @max_history 20

  @impl true
  def mount(_params, _session, socket) do
    {:ok, agent} = Agents.get_or_create_default_agent()

    active_thoughts =
      agent.id
      |> Thoughts.list()
      |> Enum.map(&normalize_thought/1)

    # Load recent thought history from trajectory so the page isn't empty on load
    thought_history = load_recent_thought_history(agent.id)

    socket =
      socket
      |> assign(:page_title, "Thought Tree")
      |> assign(:agent, agent)
      |> assign(:active_thoughts, active_thoughts)
      |> assign(:thought_history, thought_history)
      |> assign(:substrate_running, substrate_running?(agent.id))

    if connected?(socket) do
      Phoenix.PubSub.subscribe(Lincoln.PubSub, PubSubBroadcaster.thought_topic(agent.id))
    end

    {:ok, socket}
  end

  # ============================================================================
  # PubSub Handlers
  # ============================================================================

  @impl true
  def handle_info({:thought_spawned, thought_id, belief_statement, tier, parent_id}, socket) do
    new_thought = %{
      id: thought_id,
      belief_statement: belief_statement,
      tier: tier,
      status: :executing,
      started_at: DateTime.utc_now(),
      completed_at: nil,
      result: nil,
      parent_id: parent_id
    }

    active = [new_thought | socket.assigns.active_thoughts]
    {:noreply, assign(socket, :active_thoughts, active)}
  end

  def handle_info({:thought_completed, thought_id, result}, socket) do
    {completed, remaining} =
      Enum.split_with(socket.assigns.active_thoughts, fn t -> t.id == thought_id end)

    history_entry =
      case completed do
        [t | _] ->
          %{t | status: :completed, result: result, completed_at: DateTime.utc_now()}

        [] ->
          %{
            id: thought_id,
            status: :completed,
            result: result,
            belief_statement: "Unknown",
            tier: :local,
            started_at: DateTime.utc_now(),
            completed_at: DateTime.utc_now(),
            parent_id: nil
          }
      end

    history = [history_entry | socket.assigns.thought_history] |> Enum.take(@max_history)

    {:noreply,
     socket
     |> assign(:active_thoughts, remaining)
     |> assign(:thought_history, history)}
  end

  def handle_info({:thought_failed, thought_id, reason}, socket) do
    {failed, remaining} =
      Enum.split_with(socket.assigns.active_thoughts, fn t -> t.id == thought_id end)

    history_entry =
      case failed do
        [t | _] ->
          %{t | status: :failed, result: inspect(reason), completed_at: DateTime.utc_now()}

        [] ->
          %{
            id: thought_id,
            status: :failed,
            result: inspect(reason),
            belief_statement: "Unknown",
            tier: :local,
            started_at: DateTime.utc_now(),
            completed_at: DateTime.utc_now(),
            parent_id: nil
          }
      end

    history = [history_entry | socket.assigns.thought_history] |> Enum.take(@max_history)

    {:noreply,
     socket
     |> assign(:active_thoughts, remaining)
     |> assign(:thought_history, history)}
  end

  def handle_info({:thought_interrupted, thought_id, _reason}, socket) do
    {interrupted, remaining} =
      Enum.split_with(socket.assigns.active_thoughts, fn t -> t.id == thought_id end)

    history_entry =
      case interrupted do
        [t | _] ->
          %{t | status: :interrupted, result: "Preempted", completed_at: DateTime.utc_now()}

        [] ->
          %{
            id: thought_id,
            status: :interrupted,
            result: "Preempted",
            belief_statement: "Unknown",
            tier: :local,
            started_at: DateTime.utc_now(),
            completed_at: DateTime.utc_now(),
            parent_id: nil
          }
      end

    history = [history_entry | socket.assigns.thought_history] |> Enum.take(@max_history)

    {:noreply,
     socket
     |> assign(:active_thoughts, remaining)
     |> assign(:thought_history, history)}
  end

  def handle_info(_msg, socket), do: {:noreply, socket}

  # ============================================================================
  # Render
  # ============================================================================

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash}>
      <div class="container mx-auto p-4 max-w-5xl">
        <%!-- Header --%>
        <.page_header
          title="Thought Tree"
          subtitle="Each row is a supervised OTP process with its own lifecycle"
          icon="hero-cpu-chip"
          icon_color="text-primary"
        >
          <:actions>
            <.status_indicator
              status={if @substrate_running, do: :online, else: :offline}
              label={if @substrate_running, do: "Substrate Running", else: "Substrate Offline"}
              pulse={@substrate_running}
            />
          </:actions>
        </.page_header>

        <%!-- Active Thoughts --%>
        <div class="mb-6">
          <div class="flex items-center gap-2 mb-3">
            <span class="text-[10px] font-terminal uppercase tracking-widest text-base-content/40">
              Active
            </span>
            <.badge type={:primary}>{length(@active_thoughts)}</.badge>
          </div>

          <%= if @active_thoughts == [] do %>
            <.empty_state
              icon="hero-cpu-chip"
              title={
                if @substrate_running,
                  do: "Waiting for next tick...",
                  else: "Start substrate to see thoughts"
              }
              description=""
            />
          <% else %>
            <% roots = Enum.filter(@active_thoughts, fn t -> is_nil(t.parent_id) end) %>
            <% children_by_parent =
              @active_thoughts
              |> Enum.filter(fn t -> t.parent_id end)
              |> Enum.group_by(& &1.parent_id) %>
            <% root_ids = MapSet.new(roots, & &1.id) %>
            <% orphans =
              @active_thoughts
              |> Enum.filter(fn t -> t.parent_id && not MapSet.member?(root_ids, t.parent_id) end) %>

            <div class="space-y-2">
              <%= for root <- roots do %>
                <div class="border-2 border-primary/20 rounded p-3 bg-primary/5 shadow-brutal-sm hover:border-primary/40 transition-colors">
                  <div class="flex items-start justify-between gap-3">
                    <div class="flex-1 min-w-0">
                      <p class="text-sm text-base-content truncate">
                        {root.belief_statement}
                      </p>
                      <div class="flex items-center gap-3 mt-1">
                        <.badge type={tier_badge_type(root.tier)}>{tier_label(root.tier)}</.badge>
                        <span class="text-[10px] font-terminal uppercase tracking-widest text-base-content/40">
                          {format_duration(root.started_at)}
                        </span>
                        <span class="font-mono text-base-content/20 text-xs">
                          {String.slice(root.id, 0, 8)}
                        </span>
                      </div>
                    </div>
                    <div>
                      <.thought_status_badge status={root.status} />
                    </div>
                  </div>
                </div>

                <%= for child <- Map.get(children_by_parent, root.id, []) do %>
                  <div class="ml-6 border-2 border-base-content/10 rounded p-2 bg-base-200/20 border-l-2 border-l-info/30 shadow-brutal-sm hover:border-base-content/20 transition-colors">
                    <div class="flex items-center justify-between gap-2">
                      <div class="flex-1 min-w-0">
                        <p class="text-xs text-base-content/70 truncate">
                          {child.belief_statement}
                        </p>
                        <div class="flex items-center gap-2 mt-0.5">
                          <.badge type={tier_badge_type(child.tier)}>{tier_label(child.tier)}</.badge>
                          <span class="text-[10px] font-terminal uppercase tracking-widest text-base-content/40">
                            {format_duration(child.started_at)}
                          </span>
                          <span class="font-mono text-base-content/15 text-[10px]">
                            {String.slice(child.id, 0, 8)}
                          </span>
                        </div>
                      </div>
                      <.thought_status_badge status={child.status} />
                    </div>
                  </div>
                <% end %>
              <% end %>

              <%= for orphan <- orphans do %>
                <div class="ml-2 border-2 border-base-content/10 rounded p-2 bg-base-200/20 hover:border-base-content/15 transition-colors opacity-70">
                  <div class="flex items-center justify-between gap-2">
                    <div class="flex-1 min-w-0">
                      <p class="text-xs text-base-content/50 truncate">
                        {orphan.belief_statement}
                      </p>
                      <div class="flex items-center gap-2 mt-0.5">
                        <.badge type={tier_badge_type(orphan.tier)}>{tier_label(orphan.tier)}</.badge>
                        <span class="text-[10px] font-terminal uppercase tracking-widest text-base-content/40">
                          {format_duration(orphan.started_at)}
                        </span>
                      </div>
                    </div>
                    <.thought_status_badge status={orphan.status} />
                  </div>
                </div>
              <% end %>
            </div>
          <% end %>
        </div>

        <%!-- Recent History --%>
        <div>
          <div class="flex items-center gap-2 mb-3">
            <span class="text-[10px] font-terminal uppercase tracking-widest text-base-content/40">
              Recent
            </span>
            <.badge type={:default}>{length(@thought_history)}</.badge>
          </div>

          <%= if @thought_history == [] do %>
            <.empty_state
              icon="hero-clock"
              title="No completed thoughts yet"
              description=""
            />
          <% else %>
            <div class="space-y-1">
              <%= for thought <- @thought_history do %>
                <div class="border-2 border-base-content/5 rounded p-2 bg-base-200/30 hover:border-base-content/10 transition-colors">
                  <div class="flex items-center gap-3">
                    <div class="flex-1 min-w-0">
                      <p class="text-xs text-base-content/70 truncate">
                        {thought.belief_statement}
                      </p>
                    </div>
                    <.badge type={tier_badge_type(thought.tier)}>{tier_label(thought.tier)}</.badge>
                    <.thought_status_badge status={thought.status} />
                    <span class="text-[10px] font-terminal uppercase tracking-widest text-base-content/40">
                      {format_duration(thought.started_at, thought.completed_at)}
                    </span>
                  </div>
                </div>
              <% end %>
            </div>
          <% end %>
        </div>
      </div>
    </Layouts.app>
    """
  end

  # ============================================================================
  # Components
  # ============================================================================

  attr(:status, :atom, required: true)

  defp thought_status_badge(assigns) do
    {badge_class, badge_text} = status_badge_attrs(assigns.status)
    assigns = assign(assigns, badge_class: badge_class, badge_text: badge_text)

    ~H"""
    <span class={["px-2 py-0.5 rounded text-xs font-terminal", @badge_class]}>
      {@badge_text}
    </span>
    """
  end

  # ============================================================================
  # Helpers
  # ============================================================================

  defp normalize_thought(thought) do
    belief_statement =
      if is_map(thought.belief) do
        Map.get(thought.belief, :statement, inspect(thought.belief))
      else
        inspect(thought.belief)
      end

    %{
      id: thought.id,
      belief_statement: belief_statement,
      tier: thought.tier,
      status: thought.status,
      started_at: thought.started_at,
      completed_at: thought.completed_at,
      result: thought.result,
      parent_id: thought.parent_id
    }
  end

  defp load_recent_thought_history(agent_id) do
    agent_id
    |> Substrate.list_recent_thought_events(@max_history)
    |> Enum.map(fn event ->
      data = event.event_data

      %{
        id: data["thought_id"] || event.id,
        belief_statement: data["belief_statement"] || data["result_summary"] || "Unknown",
        tier: String.to_existing_atom(event.inference_tier || "local"),
        status: if(event.event_type == "thought_completed", do: :completed, else: :failed),
        result: data["result_summary"],
        started_at: event.inserted_at,
        completed_at: event.inserted_at,
        parent_id: nil
      }
    end)
  end

  defp substrate_running?(agent_id) do
    case Substrate.get_agent_state(agent_id) do
      {:ok, _} -> true
      _ -> false
    end
  end

  defp tier_badge_type(:local), do: :default
  defp tier_badge_type(:ollama), do: :info
  defp tier_badge_type(:claude), do: :warning
  defp tier_badge_type(_), do: :default

  defp tier_label(:local), do: "L0"
  defp tier_label(:ollama), do: "L1"
  defp tier_label(:claude), do: "L2"
  defp tier_label(t), do: to_string(t)

  defp status_badge_attrs(:executing), do: {"bg-info/20 text-info", "executing"}
  defp status_badge_attrs(:initializing), do: {"bg-info/20 text-info", "initializing"}
  defp status_badge_attrs(:awaiting_llm), do: {"bg-warning/20 text-warning", "awaiting LLM"}
  defp status_badge_attrs(:completed), do: {"bg-success/20 text-success", "completed"}
  defp status_badge_attrs(:failed), do: {"bg-error/20 text-error", "failed"}
  defp status_badge_attrs(:interrupted), do: {"bg-warning/20 text-warning", "interrupted"}
  defp status_badge_attrs(_), do: {"bg-base-content/10 text-base-content/50", "unknown"}

  defp format_duration(started_at, completed_at \\ nil) do
    finish = completed_at || DateTime.utc_now()

    case {started_at, finish} do
      {%DateTime{} = s, %DateTime{} = f} ->
        ms = DateTime.diff(f, s, :millisecond)

        if ms < 1000 do
          "#{ms}ms"
        else
          "#{Float.round(ms / 1000, 1)}s"
        end

      _ ->
        "-"
    end
  end
end
