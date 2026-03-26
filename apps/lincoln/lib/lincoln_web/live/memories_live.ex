defmodule LincolnWeb.MemoriesLive do
  @moduledoc """
  LiveView for the Memory Bank - viewing agent memories.
  Uses daisyUI tabs, cards, badges, and progress components.
  """
  use LincolnWeb, :live_view

  alias Lincoln.{Agents, Memory}

  @impl true
  def mount(_params, _session, socket) do
    {:ok, agent} = Agents.get_or_create_default_agent()

    socket =
      socket
      |> assign(:agent, agent)
      |> assign(:page_title, "Memory Bank")
      |> assign(:filter, "all")
      |> load_memories()

    if connected?(socket) do
      Phoenix.PubSub.subscribe(Lincoln.PubSub, "agent:#{agent.id}:memories")
    end

    {:ok, socket}
  end

  @impl true
  def handle_params(%{"id" => id}, _uri, socket) do
    memory = Memory.get_memory!(id)

    socket =
      socket
      |> assign(:selected_memory, memory)
      |> assign(:page_title, "Memory: #{truncate(memory.content, 30)}")

    {:noreply, socket}
  end

  def handle_params(_params, _uri, socket) do
    {:noreply, assign(socket, :selected_memory, nil)}
  end

  @impl true
  def handle_event("filter", %{"filter" => filter}, socket) do
    socket =
      socket
      |> assign(:filter, filter)
      |> load_memories()

    {:noreply, socket}
  end

  def handle_event("close_detail", _params, socket) do
    {:noreply, push_patch(socket, to: ~p"/memories")}
  end

  @impl true
  def handle_info({:memory_created, memory}, socket) do
    {:noreply, stream_insert(socket, :memories, memory, at: 0)}
  end

  def handle_info({:memory_updated, memory}, socket) do
    {:noreply, stream_insert(socket, :memories, memory)}
  end

  defp load_memories(socket) do
    agent = socket.assigns.agent
    filter = socket.assigns.filter

    memories =
      case filter do
        "observation" ->
          Memory.list_memories(agent, memory_type: "observation", limit: 50)

        "reflection" ->
          Memory.list_memories(agent, memory_type: "reflection", limit: 50)

        "conversation" ->
          Memory.list_memories(agent, memory_type: "conversation", limit: 50)

        "plan" ->
          Memory.list_memories(agent, memory_type: "plan", limit: 50)

        "important" ->
          Memory.list_memories(agent, min_importance: 7, limit: 50)

        _ ->
          Memory.list_recent_memories(agent, 168, limit: 50)
      end

    stream(socket, :memories, memories, reset: true)
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
              <.icon name="hero-archive-box" class="size-6 text-accent" /> Memory Bank
            </h1>
            <p class="text-sm font-terminal text-base-content/60 mt-1">
              Experience storage for {@agent.name}
            </p>
          </div>
          <a href="/" class="btn btn-outline btn-accent btn-sm font-terminal uppercase">
            <.icon name="hero-arrow-left" class="size-4" /> Dashboard
          </a>
        </div>
        
    <!-- Filter Tabs -->
        <div role="tablist" class="tabs tabs-boxed bg-base-200 border-2 border-accent w-fit">
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
          <!-- Memories List -->
          <div class={["flex-1", @selected_memory && "lg:max-w-md"]}>
            <div id="memories-list" phx-update="stream" class="space-y-3">
              <!-- Empty state -->
              <div class="hidden only:flex flex-col items-center justify-center p-12 border-2 border-dashed border-base-content/20">
                <.icon name="hero-archive-box" class="size-12 text-base-content/20 mb-3" />
                <p class="font-terminal text-sm uppercase text-base-content/40">
                  No memories match this filter
                </p>
              </div>
              <!-- Memory cards -->
              <.memory_card
                :for={{dom_id, memory} <- @streams.memories}
                id={dom_id}
                memory={memory}
                selected={@selected_memory && @selected_memory.id == memory.id}
              />
            </div>
          </div>
          
    <!-- Detail Panel -->
          <%= if @selected_memory do %>
            <.memory_detail memory={@selected_memory} />
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
      {"all", "Recent"},
      {"observation", "Observe"},
      {"reflection", "Reflect"},
      {"conversation", "Converse"},
      {"plan", "Plan"},
      {"important", "Important"}
    ]
  end

  attr(:id, :string, required: true)
  attr(:memory, :map, required: true)
  attr(:selected, :boolean, default: false)

  defp memory_card(assigns) do
    ~H"""
    <.link
      id={@id}
      patch={~p"/memories/#{@memory.id}"}
      class={[
        "card bg-base-200 border-2 hover-lift transition-all cursor-pointer",
        @selected && "border-accent bg-base-300 shadow-brutal",
        !@selected && "border-accent/30 hover:border-accent"
      ]}
    >
      <div class="card-body p-4">
        <p class="text-sm font-terminal line-clamp-2">{truncate(@memory.content, 150)}</p>
        <div class="card-actions justify-between items-center mt-2">
          <div class="flex items-center gap-2">
            <span class={[
              "badge badge-sm font-terminal uppercase",
              memory_badge_class(@memory.memory_type)
            ]}>
              {@memory.memory_type}
            </span>
            <span class="badge badge-ghost badge-sm font-terminal">x{@memory.access_count}</span>
          </div>
          <.importance_indicator importance={@memory.importance} />
        </div>
      </div>
    </.link>
    """
  end

  attr(:memory, :map, required: true)

  defp memory_detail(assigns) do
    ~H"""
    <div class="flex-1 lg:max-w-lg">
      <div class="card bg-base-200 border-2 border-accent sticky top-20">
        <!-- Header -->
        <div class="flex items-center justify-between px-4 py-3 border-b-2 border-accent bg-base-300">
          <h3 class="font-terminal text-sm font-bold uppercase tracking-wider flex items-center gap-2">
            <.icon name="hero-document-magnifying-glass" class="size-4 text-accent" /> Memory Analysis
          </h3>
          <button
            phx-click="close_detail"
            class="btn btn-ghost btn-sm btn-square hover:btn-error"
          >
            <.icon name="hero-x-mark" class="size-4" />
          </button>
        </div>

        <div class="card-body p-4 space-y-4">
          <!-- Content -->
          <div>
            <label class="text-xs font-terminal uppercase tracking-wider text-base-content/50">
              Content
            </label>
            <p class="mt-1 font-terminal whitespace-pre-wrap">{@memory.content}</p>
          </div>
          
    <!-- Summary -->
          <%= if @memory.summary do %>
            <div class="alert">
              <.icon name="hero-document-text" class="size-5" />
              <div>
                <div class="text-xs font-terminal uppercase font-bold">Summary</div>
                <div class="text-sm font-terminal italic">{@memory.summary}</div>
              </div>
            </div>
          <% end %>
          
    <!-- Stats -->
          <div class="stats stats-vertical sm:stats-horizontal bg-base-300 border border-accent/30 w-full">
            <div class="stat p-3">
              <div class="stat-title text-xs font-terminal uppercase">Importance</div>
              <div class="stat-value text-xl font-terminal text-accent">
                {@memory.importance}<span class="text-base text-base-content/30">/10</span>
              </div>
              <div class="stat-desc">
                <progress
                  class="progress progress-accent w-full h-1"
                  value={@memory.importance * 10}
                  max="100"
                />
              </div>
            </div>
            <div class="stat p-3">
              <div class="stat-title text-xs font-terminal uppercase">Access Count</div>
              <div class="stat-value text-xl font-terminal">{@memory.access_count}</div>
              <div class="stat-desc font-terminal">times retrieved</div>
            </div>
          </div>
          
    <!-- Metadata -->
          <div class="divider text-xs font-terminal uppercase text-base-content/40">Details</div>

          <div class="space-y-2">
            <div class="flex items-center justify-between">
              <span class="text-xs font-terminal text-base-content/50 uppercase">Type</span>
              <span class={[
                "badge badge-sm font-terminal uppercase",
                memory_badge_class(@memory.memory_type)
              ]}>
                {@memory.memory_type}
              </span>
            </div>
            <%= if @memory.last_accessed_at do %>
              <div class="flex items-center justify-between">
                <span class="text-xs font-terminal text-base-content/50 uppercase">
                  Last Accessed
                </span>
                <span class="font-terminal text-xs text-base-content/60">
                  {format_datetime(@memory.last_accessed_at)}
                </span>
              </div>
            <% end %>
            <div class="flex items-center justify-between">
              <span class="text-xs font-terminal text-base-content/50 uppercase">Created</span>
              <span class="font-terminal text-xs text-base-content/60">
                {format_datetime(@memory.inserted_at)}
              </span>
            </div>
          </div>
          
    <!-- Source Context -->
          <%= if @memory.source_context && @memory.source_context != %{} do %>
            <div class="collapse collapse-arrow bg-base-300 border border-accent/20">
              <input type="checkbox" />
              <div class="collapse-title text-xs font-terminal uppercase font-bold">
                Source Context
              </div>
              <div class="collapse-content">
                <pre class="text-xs font-terminal overflow-x-auto" phx-no-curly-interpolation>{inspect(@memory.source_context, pretty: true)}</pre>
              </div>
            </div>
          <% end %>
          
    <!-- Related Beliefs -->
          <%= if @memory.related_belief_ids && @memory.related_belief_ids != [] do %>
            <div class="alert alert-info">
              <.icon name="hero-link" class="size-5" />
              <div>
                <div class="text-xs font-terminal uppercase font-bold">Linked Beliefs</div>
                <div class="text-sm font-terminal">
                  {length(@memory.related_belief_ids)} belief(s) connected
                </div>
              </div>
              <a href="/beliefs" class="btn btn-ghost btn-xs font-terminal">View</a>
            </div>
          <% end %>
        </div>
      </div>
    </div>
    """
  end

  attr(:importance, :integer, required: true)

  defp importance_indicator(assigns) do
    ~H"""
    <div
      class="flex items-center gap-1 tooltip tooltip-left"
      data-tip={"Importance: #{@importance}/10"}
    >
      <span
        :for={i <- 1..5}
        class={[
          "w-1.5 h-3",
          i <= div(@importance, 2) && "bg-accent",
          i > div(@importance, 2) && "bg-base-content/20"
        ]}
      />
    </div>
    """
  end

  # Style helpers
  defp memory_badge_class("observation"), do: "badge-info"
  defp memory_badge_class("reflection"), do: "badge-secondary"
  defp memory_badge_class("conversation"), do: "badge-warning"
  defp memory_badge_class("plan"), do: "badge-primary"
  defp memory_badge_class(_), do: "badge-ghost"

  defp truncate(text, max_length) when is_binary(text) do
    if String.length(text) > max_length do
      String.slice(text, 0, max_length) <> "..."
    else
      text
    end
  end

  defp truncate(_, _), do: ""

  defp format_datetime(nil), do: "-"

  defp format_datetime(datetime) do
    Calendar.strftime(datetime, "%Y-%m-%d %H:%M")
  end
end
