defmodule LincolnWeb.MemoriesLive do
  @moduledoc """
  LiveView for the Memory Bank - viewing agent memories.
  Uses daisyUI tabs, cards, badges, and progress components.
  """
  use LincolnWeb, :live_view

  alias Lincoln.{Agents, Memory}

  @per_page 20

  @impl true
  def mount(_params, _session, socket) do
    {:ok, agent} = Agents.get_or_create_default_agent()

    socket =
      socket
      |> assign(:agent, agent)
      |> assign(:page_title, "Memory Bank")
      |> assign(:filter, "all")
      |> assign(:page, 1)
      |> assign(:per_page, @per_page)
      |> assign(:end_of_list?, false)
      |> stream(:memories, [])

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
      |> maybe_paginate_memories()

    {:noreply, socket}
  end

  def handle_params(_params, _uri, socket) do
    socket =
      socket
      |> assign(:selected_memory, nil)
      |> maybe_paginate_memories()

    {:noreply, socket}
  end

  defp maybe_paginate_memories(socket) do
    if socket.assigns.page == 1 do
      paginate_memories(socket, 1)
    else
      socket
    end
  end

  @impl true
  def handle_event("filter", %{"filter" => filter}, socket) do
    socket =
      socket
      |> assign(:filter, filter)
      |> assign(:page, 1)
      |> assign(:end_of_list?, false)
      |> paginate_memories(1, reset: true)

    {:noreply, socket}
  end

  def handle_event("close_detail", _params, socket) do
    {:noreply, push_patch(socket, to: ~p"/memories")}
  end

  def handle_event("load-more", _, socket) do
    {:noreply, paginate_memories(socket, socket.assigns.page + 1)}
  end

  @impl true
  def handle_info({:memory_created, memory}, socket) do
    {:noreply, stream_insert(socket, :memories, memory, at: 0)}
  end

  def handle_info({:memory_updated, memory}, socket) do
    {:noreply, stream_insert(socket, :memories, memory)}
  end

  defp paginate_memories(socket, new_page, opts \\ []) do
    %{per_page: per_page, page: cur_page, agent: agent, filter: filter} = socket.assigns
    reset = Keyword.get(opts, :reset, false)

    offset = (new_page - 1) * per_page

    memories = fetch_filtered_memories(agent, filter, per_page, offset)

    {memories, at, limit} =
      if new_page >= cur_page do
        {memories, -1, per_page * 3 * -1}
      else
        {Enum.reverse(memories), 0, per_page * 3}
      end

    case memories do
      [] ->
        assign(socket, end_of_list?: at == -1)

      [_ | _] ->
        socket
        |> assign(:end_of_list?, false)
        |> assign(:page, new_page)
        |> stream(:memories, memories, at: at, limit: limit, reset: reset)
    end
  end

  defp fetch_filtered_memories(agent, filter, per_page, offset) do
    case filter do
      type when type in ~w(observation reflection conversation plan) ->
        Memory.list_memories(agent, memory_type: type, limit: per_page, offset: offset)

      "important" ->
        Memory.list_memories(agent, min_importance: 7, limit: per_page, offset: offset)

      _ ->
        Memory.list_recent_memories(agent, 168, limit: per_page, offset: offset)
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash}>
      <div class="space-y-6">
        <!-- Page Header -->
        <div class="flex flex-col sm:flex-row sm:items-center sm:justify-between gap-4">
          <div>
            <h1 class="text-2xl font-semibold flex items-center gap-2">
              <.icon name="hero-archive-box" class="w-6 h-6 text-accent" /> Memory Bank
            </h1>
            <p class="text-sm text-base-content/60 mt-1">
              Experience storage for {@agent.name}
            </p>
          </div>
          <a href="/" class="btn btn-ghost btn-sm">
            <.icon name="hero-arrow-left" class="w-4 h-4" /> Dashboard
          </a>
        </div>
        
    <!-- Filter Tabs -->
        <div role="tablist" class="tabs tabs-boxed bg-base-200 border border-base-300 w-fit">
          <button
            :for={{value, label} <- filter_options()}
            role="tab"
            class={["tab text-xs", @filter == value && "tab-active"]}
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
            <div
              id="memories-list"
              phx-update="stream"
              phx-viewport-bottom={!@end_of_list? && "load-more"}
              class={[
                "space-y-3",
                if(@end_of_list?, do: "pb-10", else: "pb-[calc(100vh)]")
              ]}
            >
              <!-- Empty state -->
              <div class="hidden only:flex flex-col items-center justify-center p-12 border border-dashed border-base-content/20 rounded-lg">
                <.icon name="hero-archive-box" class="w-12 h-12 text-base-content/20 mb-3" />
                <p class="text-sm text-base-content/40">
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
            <div
              :if={@end_of_list? && @page > 1}
              class="text-center py-4 text-base-content/60 text-sm"
            >
              No more memories to load
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
        "block bg-base-200 border rounded-lg p-4 transition-colors cursor-pointer",
        @selected && "border-accent bg-base-300",
        !@selected && "border-base-300 hover:border-accent/50 hover:bg-base-300/50"
      ]}
    >
      <p class="text-sm line-clamp-2">{truncate(@memory.content, 150)}</p>
      <div class="flex justify-between items-center mt-3">
        <div class="flex items-center gap-2">
          <span class={["badge badge-sm", memory_badge_class(@memory.memory_type)]}>
            {@memory.memory_type}
          </span>
          <span class="badge badge-ghost badge-sm">x{@memory.access_count}</span>
        </div>
        <.importance_indicator importance={@memory.importance} />
      </div>
    </.link>
    """
  end

  attr(:memory, :map, required: true)

  defp memory_detail(assigns) do
    ~H"""
    <div class="flex-1 lg:max-w-lg">
      <div class="bg-base-200 border border-base-300 rounded-lg sticky top-20">
        <!-- Header -->
        <div class="flex items-center justify-between px-4 py-3 border-b border-base-300">
          <h3 class="text-sm font-semibold flex items-center gap-2">
            <.icon name="hero-document-magnifying-glass" class="w-4 h-4 text-accent" />
            Memory Analysis
          </h3>
          <button
            phx-click="close_detail"
            class="btn btn-ghost btn-sm btn-square hover:btn-error"
          >
            <.icon name="hero-x-mark" class="w-4 h-4" />
          </button>
        </div>

        <div class="p-4 space-y-4">
          <!-- Content -->
          <div>
            <label class="text-xs uppercase tracking-wider text-base-content/50">
              Content
            </label>
            <p class="mt-1 whitespace-pre-wrap">{@memory.content}</p>
          </div>
          
    <!-- Summary -->
          <%= if @memory.summary do %>
            <div class="bg-base-300 rounded-lg p-3 flex gap-3">
              <.icon name="hero-document-text" class="w-5 h-5 text-base-content/60 shrink-0" />
              <div>
                <div class="text-xs uppercase font-medium text-base-content/60">Summary</div>
                <div class="text-sm italic mt-1">{@memory.summary}</div>
              </div>
            </div>
          <% end %>
          
    <!-- Stats -->
          <div class="grid grid-cols-2 gap-3">
            <div class="bg-base-300 rounded-lg p-3">
              <div class="text-xs uppercase text-base-content/60">Importance</div>
              <div class="text-xl font-semibold text-accent mt-1">
                {@memory.importance}<span class="text-base text-base-content/30">/10</span>
              </div>
              <progress
                class="progress progress-accent w-full h-1 mt-2"
                value={@memory.importance * 10}
                max="100"
              />
            </div>
            <div class="bg-base-300 rounded-lg p-3">
              <div class="text-xs uppercase text-base-content/60">Access Count</div>
              <div class="text-xl font-semibold mt-1">{@memory.access_count}</div>
              <div class="text-xs text-base-content/50 mt-1">times retrieved</div>
            </div>
          </div>
          
    <!-- Metadata -->
          <div class="divider text-xs uppercase text-base-content/40">Details</div>

          <div class="space-y-2">
            <div class="flex items-center justify-between">
              <span class="text-xs text-base-content/50 uppercase">Type</span>
              <span class={["badge badge-sm", memory_badge_class(@memory.memory_type)]}>
                {@memory.memory_type}
              </span>
            </div>
            <%= if @memory.last_accessed_at do %>
              <div class="flex items-center justify-between">
                <span class="text-xs text-base-content/50 uppercase">Last Accessed</span>
                <span class="text-xs text-base-content/60">
                  {format_datetime(@memory.last_accessed_at)}
                </span>
              </div>
            <% end %>
            <div class="flex items-center justify-between">
              <span class="text-xs text-base-content/50 uppercase">Created</span>
              <span class="text-xs text-base-content/60">
                {format_datetime(@memory.inserted_at)}
              </span>
            </div>
          </div>
          
    <!-- Source Context -->
          <%= if @memory.source_context && @memory.source_context != %{} do %>
            <div class="collapse collapse-arrow bg-base-300 rounded-lg">
              <input type="checkbox" />
              <div class="collapse-title text-xs uppercase font-medium">
                Source Context
              </div>
              <div class="collapse-content">
                <pre class="text-xs overflow-x-auto font-mono" phx-no-curly-interpolation>{inspect(@memory.source_context, pretty: true)}</pre>
              </div>
            </div>
          <% end %>
          
    <!-- Related Beliefs -->
          <%= if @memory.related_belief_ids && @memory.related_belief_ids != [] do %>
            <div class="bg-info/10 border border-info/20 rounded-lg p-3 flex items-center gap-3">
              <.icon name="hero-link" class="w-5 h-5 text-info" />
              <div class="flex-1">
                <div class="text-xs uppercase font-medium">Linked Beliefs</div>
                <div class="text-sm">
                  {length(@memory.related_belief_ids)} belief(s) connected
                </div>
              </div>
              <a href="/beliefs" class="btn btn-ghost btn-xs">View</a>
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
      class="flex items-center gap-0.5 tooltip tooltip-left"
      data-tip={"Importance: #{@importance}/10"}
    >
      <span
        :for={i <- 1..5}
        class={[
          "w-1.5 h-3 rounded-sm",
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
