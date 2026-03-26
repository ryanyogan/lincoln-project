defmodule LincolnWeb.BeliefsLive do
  @moduledoc """
  LiveView for the Belief Matrix - viewing and managing agent beliefs.
  Uses daisyUI tabs, cards, badges, and progress components.
  """
  use LincolnWeb, :live_view

  alias Lincoln.{Agents, Beliefs}

  @impl true
  def mount(_params, _session, socket) do
    {:ok, agent} = Agents.get_or_create_default_agent()

    socket =
      socket
      |> assign(:agent, agent)
      |> assign(:page_title, "Belief Matrix")
      |> assign(:filter, "all")
      |> load_beliefs()

    if connected?(socket) do
      Phoenix.PubSub.subscribe(Lincoln.PubSub, "agent:#{agent.id}:beliefs")
    end

    {:ok, socket}
  end

  @impl true
  def handle_params(%{"id" => id}, _uri, socket) do
    belief = Beliefs.get_belief!(id)

    socket =
      socket
      |> assign(:selected_belief, belief)
      |> assign(:page_title, "Belief: #{truncate(belief.statement, 30)}")

    {:noreply, socket}
  end

  def handle_params(_params, _uri, socket) do
    {:noreply, assign(socket, :selected_belief, nil)}
  end

  @impl true
  def handle_event("filter", %{"filter" => filter}, socket) do
    socket =
      socket
      |> assign(:filter, filter)
      |> load_beliefs()

    {:noreply, socket}
  end

  def handle_event("close_detail", _params, socket) do
    {:noreply, push_patch(socket, to: ~p"/beliefs")}
  end

  @impl true
  def handle_info({:belief_created, belief}, socket) do
    {:noreply, stream_insert(socket, :beliefs, belief, at: 0)}
  end

  def handle_info({:belief_updated, belief}, socket) do
    {:noreply, stream_insert(socket, :beliefs, belief)}
  end

  defp load_beliefs(socket) do
    agent = socket.assigns.agent
    filter = socket.assigns.filter

    beliefs =
      case filter do
        "high_confidence" ->
          Beliefs.list_beliefs(agent, min_confidence: 0.7)

        "low_confidence" ->
          Beliefs.list_beliefs(agent, max_confidence: 0.5)

        "active" ->
          Beliefs.list_beliefs(agent, status: "active")

        "revised" ->
          Beliefs.list_beliefs(agent, status: "revised")

        _ ->
          Beliefs.list_beliefs(agent)
      end

    stream(socket, :beliefs, beliefs, reset: true)
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash}>
      <div class="space-y-6">
        <!-- Page Header -->
        <div class="flex flex-col sm:flex-row sm:items-center sm:justify-between gap-4">
          <div>
            <h1 class="text-2xl font-black font-terminal uppercase tracking-tight flex items-center gap-2">
              <.icon name="hero-light-bulb" class="size-6 text-primary" /> Belief Matrix
            </h1>
            <p class="text-sm font-terminal text-base-content/60 mt-1">
              Knowledge structures held by {@agent.name}
            </p>
          </div>
          <a href="/" class="btn btn-outline btn-primary btn-sm font-terminal uppercase">
            <.icon name="hero-arrow-left" class="size-4" /> Dashboard
          </a>
        </div>
        
    <!-- Filter Tabs using daisyUI tabs -->
        <div role="tablist" class="tabs tabs-boxed bg-base-200 border-2 border-primary w-fit">
          <button
            :for={{value, label} <- filter_options()}
            role="tab"
            class={["tab font-terminal uppercase text-xs", @filter == value && "tab-active"]}
            phx-click="filter"
            phx-value-filter={value}
          >
            {label}
          </button>
        </div>
        
    <!-- Main Content -->
        <div class="flex flex-col lg:flex-row gap-6">
          <!-- Beliefs List -->
          <div class={["flex-1", @selected_belief && "lg:max-w-md"]}>
            <div id="beliefs-list" phx-update="stream" class="space-y-3">
              <!-- Empty state -->
              <div class="hidden only:flex flex-col items-center justify-center p-12 border-2 border-dashed border-base-content/20">
                <.icon name="hero-light-bulb" class="size-12 text-base-content/20 mb-3" />
                <p class="font-terminal text-sm uppercase text-base-content/40">
                  No beliefs match this filter
                </p>
              </div>
              <!-- Belief cards -->
              <.belief_card
                :for={{dom_id, belief} <- @streams.beliefs}
                id={dom_id}
                belief={belief}
                selected={@selected_belief && @selected_belief.id == belief.id}
              />
            </div>
          </div>
          
    <!-- Detail Panel -->
          <%= if @selected_belief do %>
            <.belief_detail belief={@selected_belief} />
          <% end %>
        </div>
      </div>
    </Layouts.app>
    """
  end

  # ============================================================================
  # Component Functions
  # ============================================================================

  defp filter_options do
    [
      {"all", "All"},
      {"high_confidence", "High Conf"},
      {"low_confidence", "Low Conf"},
      {"active", "Active"},
      {"revised", "Revised"}
    ]
  end

  attr(:id, :string, required: true)
  attr(:belief, :map, required: true)
  attr(:selected, :boolean, default: false)

  defp belief_card(assigns) do
    ~H"""
    <.link
      id={@id}
      patch={~p"/beliefs/#{@belief.id}"}
      class={[
        "card bg-base-200 border-2 hover-lift transition-all cursor-pointer",
        @selected && "border-primary bg-base-300 shadow-brutal-primary",
        !@selected && "border-primary/30 hover:border-primary"
      ]}
    >
      <div class="card-body p-4">
        <div class="flex items-start justify-between gap-3">
          <p class="text-sm font-terminal line-clamp-2 flex-1">{@belief.statement}</p>
          <div class="tooltip tooltip-left" data-tip="Confidence level">
            <span class={["badge font-terminal font-bold", confidence_badge_class(@belief.confidence)]}>
              {Float.round(@belief.confidence * 100, 0)}%
            </span>
          </div>
        </div>
        <div class="card-actions justify-start mt-2">
          <span class={[
            "badge badge-sm font-terminal uppercase",
            source_badge_class(@belief.source_type)
          ]}>
            {@belief.source_type}
          </span>
          <span class={["badge badge-sm font-terminal uppercase", status_badge_class(@belief.status)]}>
            {@belief.status}
          </span>
          <span class="badge badge-ghost badge-sm font-terminal">E:{@belief.entrenchment}</span>
        </div>
      </div>
    </.link>
    """
  end

  attr(:belief, :map, required: true)

  defp belief_detail(assigns) do
    ~H"""
    <div class="flex-1 lg:max-w-lg">
      <div class="card bg-base-200 border-2 border-primary sticky top-20">
        <!-- Header -->
        <div class="flex items-center justify-between px-4 py-3 border-b-2 border-primary bg-base-300">
          <h3 class="font-terminal text-sm font-bold uppercase tracking-wider flex items-center gap-2">
            <.icon name="hero-beaker" class="size-4 text-primary" /> Belief Analysis
          </h3>
          <button
            phx-click="close_detail"
            class="btn btn-ghost btn-sm btn-square hover:btn-error"
          >
            <.icon name="hero-x-mark" class="size-4" />
          </button>
        </div>

        <div class="card-body p-4 space-y-4">
          <!-- Statement -->
          <div>
            <label class="text-xs font-terminal uppercase tracking-wider text-base-content/50">
              Statement
            </label>
            <p class="mt-1 font-terminal">{@belief.statement}</p>
          </div>
          
    <!-- Evidence -->
          <%= if @belief.source_evidence do %>
            <div>
              <label class="text-xs font-terminal uppercase tracking-wider text-base-content/50">
                Evidence
              </label>
              <p class="mt-1 text-sm font-terminal text-base-content/80">{@belief.source_evidence}</p>
            </div>
          <% end %>
          
    <!-- Stats using daisyUI stats component -->
          <div class="stats stats-vertical sm:stats-horizontal bg-base-300 border border-primary/30 w-full">
            <div class="stat p-3">
              <div class="stat-title text-xs font-terminal uppercase">Confidence</div>
              <div class={[
                "stat-value text-xl font-terminal",
                confidence_text_class(@belief.confidence)
              ]}>
                {Float.round(@belief.confidence * 100, 1)}%
              </div>
              <div class="stat-desc">
                <progress
                  class={["progress w-full h-1", confidence_progress_class(@belief.confidence)]}
                  value={@belief.confidence * 100}
                  max="100"
                />
              </div>
            </div>
            <div class="stat p-3">
              <div class="stat-title text-xs font-terminal uppercase">Entrenchment</div>
              <div class="stat-value text-xl font-terminal">{@belief.entrenchment}</div>
              <div class="stat-desc">
                <progress
                  class="progress progress-secondary w-full h-1"
                  value={@belief.entrenchment * 10}
                  max="100"
                />
              </div>
            </div>
          </div>
          
    <!-- Metadata -->
          <div class="divider text-xs font-terminal uppercase text-base-content/40">Details</div>

          <div class="space-y-2">
            <div class="flex items-center justify-between">
              <span class="text-xs font-terminal text-base-content/50 uppercase">Source</span>
              <span class={[
                "badge badge-sm font-terminal uppercase",
                source_badge_class(@belief.source_type)
              ]}>
                {@belief.source_type}
              </span>
            </div>
            <div class="flex items-center justify-between">
              <span class="text-xs font-terminal text-base-content/50 uppercase">Status</span>
              <span class={[
                "badge badge-sm font-terminal uppercase",
                status_badge_class(@belief.status)
              ]}>
                {@belief.status}
              </span>
            </div>
            <div class="flex items-center justify-between">
              <span class="text-xs font-terminal text-base-content/50 uppercase">Revisions</span>
              <span class="font-terminal text-sm">{@belief.revision_count}</span>
            </div>
            <div class="flex items-center justify-between">
              <span class="text-xs font-terminal text-base-content/50 uppercase">Created</span>
              <span class="font-terminal text-xs text-base-content/60">
                {format_datetime(@belief.inserted_at)}
              </span>
            </div>
          </div>
          
    <!-- Contradicted warning -->
          <%= if @belief.contradicted_by_id do %>
            <div class="alert alert-error">
              <.icon name="hero-exclamation-triangle" class="size-5" />
              <div>
                <div class="font-terminal text-xs uppercase font-bold">Superseded</div>
                <div class="text-xs">This belief has been contradicted</div>
              </div>
            </div>
          <% end %>
        </div>
      </div>
    </div>
    """
  end

  # Style helpers
  defp source_badge_class("observation"), do: "badge-info"
  defp source_badge_class("inference"), do: "badge-secondary"
  defp source_badge_class("training"), do: "badge-warning"
  defp source_badge_class("testimony"), do: "badge-accent"
  defp source_badge_class(_), do: "badge-ghost"

  defp status_badge_class("active"), do: "badge-success"
  defp status_badge_class("revised"), do: "badge-warning"
  defp status_badge_class("contradicted"), do: "badge-error"
  defp status_badge_class("retracted"), do: "badge-ghost"
  defp status_badge_class(_), do: "badge-ghost"

  defp confidence_badge_class(conf) when conf >= 0.8, do: "badge-success"
  defp confidence_badge_class(conf) when conf >= 0.5, do: "badge-warning"
  defp confidence_badge_class(_), do: "badge-error"

  defp confidence_text_class(conf) when conf >= 0.8, do: "text-success"
  defp confidence_text_class(conf) when conf >= 0.5, do: "text-warning"
  defp confidence_text_class(_), do: "text-error"

  defp confidence_progress_class(conf) when conf >= 0.8, do: "progress-success"
  defp confidence_progress_class(conf) when conf >= 0.5, do: "progress-warning"
  defp confidence_progress_class(_), do: "progress-error"

  defp truncate(text, max_length) when is_binary(text) do
    if String.length(text) > max_length do
      String.slice(text, 0, max_length) <> "..."
    else
      text
    end
  end

  defp truncate(_, _), do: ""

  defp format_datetime(datetime) do
    Calendar.strftime(datetime, "%Y-%m-%d %H:%M")
  end
end
