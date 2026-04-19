defmodule LincolnWeb.BeliefsLive do
  @moduledoc """
  LiveView for the Belief Matrix - viewing and managing agent beliefs.
  Uses daisyUI tabs, cards, badges, and progress components.
  """
  use LincolnWeb, :live_view

  alias Lincoln.{Agents, Beliefs}

  @per_page 20

  @impl true
  def mount(_params, _session, socket) do
    {:ok, agent} = Agents.get_or_create_default_agent()

    socket =
      socket
      |> assign(:agent, agent)
      |> assign(:page_title, "Belief Matrix")
      |> assign(:filter, "all")
      |> assign(:page, 1)
      |> assign(:per_page, @per_page)
      |> assign(:end_of_list?, false)
      |> stream(:beliefs, [])

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
      |> maybe_paginate_beliefs()

    {:noreply, socket}
  end

  def handle_params(_params, _uri, socket) do
    socket =
      socket
      |> assign(:selected_belief, nil)
      |> maybe_paginate_beliefs()

    {:noreply, socket}
  end

  defp maybe_paginate_beliefs(socket) do
    if socket.assigns.page == 1 do
      paginate_beliefs(socket, 1)
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
      |> paginate_beliefs(1, reset: true)

    {:noreply, socket}
  end

  def handle_event("close_detail", _params, socket) do
    {:noreply, push_patch(socket, to: ~p"/beliefs")}
  end

  def handle_event("load-more", _, socket) do
    {:noreply, paginate_beliefs(socket, socket.assigns.page + 1)}
  end

  @impl true
  def handle_info({:belief_created, belief}, socket) do
    {:noreply, stream_insert(socket, :beliefs, belief, at: 0)}
  end

  def handle_info({:belief_updated, belief}, socket) do
    {:noreply, stream_insert(socket, :beliefs, belief)}
  end

  defp paginate_beliefs(socket, new_page, opts \\ []) do
    %{per_page: per_page, page: cur_page, agent: agent, filter: filter} = socket.assigns
    reset = Keyword.get(opts, :reset, false)

    offset = (new_page - 1) * per_page

    beliefs =
      case filter do
        "high_confidence" ->
          Beliefs.list_beliefs(agent, min_confidence: 0.7, limit: per_page, offset: offset)

        "low_confidence" ->
          Beliefs.list_beliefs(agent, max_confidence: 0.5, limit: per_page, offset: offset)

        "active" ->
          Beliefs.list_beliefs(agent, status: "active", limit: per_page, offset: offset)

        "revised" ->
          Beliefs.list_beliefs(agent, status: "revised", limit: per_page, offset: offset)

        _ ->
          Beliefs.list_beliefs(agent, limit: per_page, offset: offset)
      end

    {beliefs, at, limit} =
      if new_page >= cur_page do
        {beliefs, -1, per_page * 3 * -1}
      else
        {Enum.reverse(beliefs), 0, per_page * 3}
      end

    case beliefs do
      [] ->
        assign(socket, end_of_list?: at == -1)

      [_ | _] ->
        socket
        |> assign(:end_of_list?, false)
        |> assign(:page, new_page)
        |> stream(:beliefs, beliefs, at: at, limit: limit, reset: reset)
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash}>
      <div class="space-y-6">
        <.page_header
          title="Beliefs"
          subtitle={"Knowledge structures held by #{@agent.name}"}
          icon="hero-light-bulb"
          icon_color="text-primary"
        >
          <:actions>
            <.link navigate={~p"/"} class="btn btn-outline btn-sm font-terminal border-2">
              <.icon name="hero-arrow-left" class="size-4" /> Dashboard
            </.link>
          </:actions>
        </.page_header>

        <.filter_tabs options={filter_options()} active={@filter} />

        <div class="flex flex-col lg:flex-row gap-6">
          <div class={["flex-1", @selected_belief && "lg:max-w-md"]}>
            <div
              id="beliefs-list"
              phx-update="stream"
              phx-viewport-bottom={!@end_of_list? && "load-more"}
              class={["space-y-3", if(@end_of_list?, do: "pb-10", else: "pb-[calc(100vh)]")]}
            >
              <div class="hidden only:flex flex-col items-center justify-center p-12 border-2 border-dashed border-base-300">
                <.icon name="hero-light-bulb" class="size-10 text-base-content/20 mb-3" />
                <p class="text-sm font-terminal text-base-content/40">No beliefs match this filter</p>
              </div>
              <.belief_card
                :for={{dom_id, belief} <- @streams.beliefs}
                id={dom_id}
                belief={belief}
                selected={@selected_belief && @selected_belief.id == belief.id}
              />
            </div>
            <.load_more end_of_list?={@end_of_list?} />
          </div>

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
        "block bg-base-200 border-2 p-4 hover-lift transition-all",
        @selected && "border-primary bg-base-300 shadow-brutal-sm",
        !@selected && "border-base-300 hover:border-primary/40"
      ]}
    >
      <div class="flex items-start justify-between gap-3">
        <p class="text-sm font-terminal line-clamp-2 flex-1">{@belief.statement}</p>
        <.badge type={confidence_badge_type(@belief.confidence)}>
          {Float.round(@belief.confidence * 100, 0)}%
        </.badge>
      </div>
      <div class="flex items-center gap-2 mt-3">
        <.badge type={source_badge_type(@belief.source_type)}>{@belief.source_type}</.badge>
        <.badge type={status_badge_type(@belief.status)}>{@belief.status}</.badge>
        <span class="text-[10px] font-terminal text-base-content/40">E:{@belief.entrenchment}</span>
      </div>
    </.link>
    """
  end

  attr(:belief, :map, required: true)

  defp belief_detail(assigns) do
    ~H"""
    <div class="flex-1 lg:max-w-lg">
      <div class="bg-base-200 border-2 border-primary/40 sticky top-20 shadow-brutal">
        <div class="flex items-center justify-between px-4 py-2.5 border-b-2 border-primary/30 bg-base-300/50">
          <h3 class="font-terminal font-bold text-sm uppercase flex items-center gap-2">
            <.icon name="hero-beaker" class="size-4 text-primary" /> Belief Analysis
          </h3>
          <button
            phx-click="close_detail"
            class="btn btn-ghost btn-sm btn-square hover:btn-error"
            aria-label="Close detail"
          >
            <.icon name="hero-x-mark" class="size-4" />
          </button>
        </div>

        <div class="p-4 space-y-4">
          <div>
            <label class="text-[10px] font-terminal uppercase tracking-widest text-base-content/40">
              Statement
            </label>
            <p class="mt-1 font-terminal text-sm">{@belief.statement}</p>
          </div>

          <%= if @belief.source_evidence do %>
            <div>
              <label class="text-[10px] font-terminal uppercase tracking-widest text-base-content/40">
                Evidence
              </label>
              <p class="mt-1 text-sm text-base-content/70">{@belief.source_evidence}</p>
            </div>
          <% end %>

          <div class="grid grid-cols-2 gap-3">
            <div class="bg-base-300 border-2 border-base-300 p-3">
              <div class="text-[10px] font-terminal uppercase tracking-widest text-base-content/40">
                Confidence
              </div>
              <div class={[
                "text-xl font-bold font-terminal",
                confidence_text_class(@belief.confidence)
              ]}>
                {Float.round(@belief.confidence * 100, 1)}%
              </div>
              <progress
                class={["progress w-full h-1.5 mt-1", confidence_progress_class(@belief.confidence)]}
                value={@belief.confidence * 100}
                max="100"
              />
            </div>
            <div class="bg-base-300 border-2 border-base-300 p-3">
              <div class="text-[10px] font-terminal uppercase tracking-widest text-base-content/40">
                Entrenchment
              </div>
              <div class="text-xl font-bold font-terminal">{@belief.entrenchment}</div>
              <progress
                class="progress progress-secondary w-full h-1.5 mt-1"
                value={@belief.entrenchment * 10}
                max="100"
              />
            </div>
          </div>

          <div class="divider text-[10px] font-terminal uppercase text-base-content/30 tracking-widest">
            Details
          </div>

          <div class="space-y-2 text-sm font-terminal">
            <div class="flex items-center justify-between">
              <span class="text-base-content/40">Source</span>
              <.badge type={source_badge_type(@belief.source_type)}>{@belief.source_type}</.badge>
            </div>
            <div class="flex items-center justify-between">
              <span class="text-base-content/40">Status</span>
              <.badge type={status_badge_type(@belief.status)}>{@belief.status}</.badge>
            </div>
            <div class="flex items-center justify-between">
              <span class="text-base-content/40">Revisions</span>
              <span class="font-bold">{@belief.revision_count}</span>
            </div>
            <div class="flex items-center justify-between">
              <span class="text-base-content/40">Created</span>
              <span class="text-xs text-base-content/50">{format_datetime(@belief.inserted_at)}</span>
            </div>
          </div>

          <%= if @belief.contradicted_by_id do %>
            <div class="alert alert-error border-2">
              <.icon name="hero-exclamation-triangle" class="size-5" />
              <div>
                <div class="text-xs font-terminal uppercase font-bold">Superseded</div>
                <div class="text-xs font-terminal">This belief has been contradicted</div>
              </div>
            </div>
          <% end %>
        </div>
      </div>
    </div>
    """
  end

  # Style helpers — return badge type atoms
  defp source_badge_type("observation"), do: :info
  defp source_badge_type("inference"), do: :secondary
  defp source_badge_type("training"), do: :warning
  defp source_badge_type("testimony"), do: :accent
  defp source_badge_type(_), do: :default

  defp status_badge_type("active"), do: :success
  defp status_badge_type("revised"), do: :warning
  defp status_badge_type("contradicted"), do: :error
  defp status_badge_type("retracted"), do: :default
  defp status_badge_type(_), do: :default

  defp confidence_badge_type(conf) when conf >= 0.8, do: :success
  defp confidence_badge_type(conf) when conf >= 0.5, do: :warning
  defp confidence_badge_type(_), do: :error

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
