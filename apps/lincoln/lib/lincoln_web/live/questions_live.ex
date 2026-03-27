defmodule LincolnWeb.QuestionsLive do
  @moduledoc """
  LiveView for the Query Terminal - viewing and managing questions.
  Uses daisyUI tabs, cards, badges, and modal components.
  """
  use LincolnWeb, :live_view

  alias Lincoln.{Agents, Questions}

  @per_page 20

  @impl true
  def mount(_params, _session, socket) do
    {:ok, agent} = Agents.get_or_create_default_agent()

    socket =
      socket
      |> assign(:agent, agent)
      |> assign(:page_title, "Query Terminal")
      |> assign(:filter, "open")
      |> assign(:page, 1)
      |> assign(:per_page, @per_page)
      |> assign(:end_of_list?, false)
      |> stream(:questions, [])

    if connected?(socket) do
      Phoenix.PubSub.subscribe(Lincoln.PubSub, "agent:#{agent.id}:questions")
    end

    {:ok, socket}
  end

  @impl true
  def handle_params(%{"id" => id}, _uri, socket) do
    question = Questions.get_question!(id)
    findings = Questions.list_findings_for_question(question)

    socket =
      socket
      |> assign(:selected_question, question)
      |> assign(:question_findings, findings)
      |> assign(:page_title, "Query: #{truncate(question.question, 30)}")
      |> maybe_paginate_questions()

    {:noreply, socket}
  end

  def handle_params(_params, _uri, socket) do
    socket =
      socket
      |> assign(:selected_question, nil)
      |> assign(:question_findings, [])
      |> maybe_paginate_questions()

    {:noreply, socket}
  end

  defp maybe_paginate_questions(socket) do
    if socket.assigns.page == 1 do
      paginate_questions(socket, 1)
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
      |> paginate_questions(1, reset: true)

    {:noreply, socket}
  end

  def handle_event("close_detail", _params, socket) do
    {:noreply, push_patch(socket, to: ~p"/questions")}
  end

  def handle_event("load-more", _, socket) do
    {:noreply, paginate_questions(socket, socket.assigns.page + 1)}
  end

  def handle_event("abandon", %{"id" => id}, socket) do
    question = Questions.get_question!(id)
    {:ok, _} = Questions.abandon_question(question)

    socket =
      socket
      |> assign(:page, 1)
      |> assign(:end_of_list?, false)
      |> paginate_questions(1, reset: true)
      |> put_flash(:info, "Query abandoned")

    {:noreply, push_patch(socket, to: ~p"/questions")}
  end

  @impl true
  def handle_info({:question_created, question}, socket) do
    {:noreply, stream_insert(socket, :questions, question, at: 0)}
  end

  def handle_info({:question_updated, question}, socket) do
    {:noreply, stream_insert(socket, :questions, question)}
  end

  def handle_info({:question_resolved, question, _finding}, socket) do
    if socket.assigns.filter == "open" do
      {:noreply, stream_delete(socket, :questions, question)}
    else
      {:noreply, stream_insert(socket, :questions, question)}
    end
  end

  defp paginate_questions(socket, new_page, opts \\ []) do
    %{per_page: per_page, page: cur_page, agent: agent, filter: filter} = socket.assigns
    reset = Keyword.get(opts, :reset, false)

    offset = (new_page - 1) * per_page

    questions =
      case filter do
        "open" ->
          Questions.list_open_questions(agent, limit: per_page, offset: offset)

        "answered" ->
          Questions.list_questions(agent, status: "answered", limit: per_page, offset: offset)

        "abandoned" ->
          Questions.list_questions(agent, status: "abandoned", limit: per_page, offset: offset)

        _ ->
          Questions.list_questions(agent, limit: per_page, offset: offset)
      end

    {questions, at, limit} =
      if new_page >= cur_page do
        {questions, -1, per_page * 3 * -1}
      else
        {Enum.reverse(questions), 0, per_page * 3}
      end

    case questions do
      [] ->
        assign(socket, end_of_list?: at == -1)

      [_ | _] ->
        socket
        |> assign(:end_of_list?, false)
        |> assign(:page, new_page)
        |> stream(:questions, questions, at: at, limit: limit, reset: reset)
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
              <.icon name="hero-question-mark-circle" class="w-6 h-6 text-secondary" /> Query Terminal
            </h1>
            <p class="text-sm text-base-content/60 mt-1">
              Active investigations by {@agent.name}
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
          <!-- Questions List -->
          <div class={["flex-1", @selected_question && "lg:max-w-md"]}>
            <div
              id="questions-list"
              phx-update="stream"
              phx-viewport-bottom={!@end_of_list? && "load-more"}
              class={[
                "space-y-3",
                if(@end_of_list?, do: "pb-10", else: "pb-[calc(100vh)]")
              ]}
            >
              <!-- Empty state -->
              <div class="hidden only:flex flex-col items-center justify-center p-12 border border-dashed border-base-content/20 rounded-lg">
                <.icon name="hero-question-mark-circle" class="w-12 h-12 text-base-content/20 mb-3" />
                <p class="text-sm text-base-content/40">
                  No queries match this filter
                </p>
              </div>
              <!-- Question cards -->
              <.question_card
                :for={{dom_id, question} <- @streams.questions}
                id={dom_id}
                question={question}
                selected={@selected_question && @selected_question.id == question.id}
              />
            </div>
            <div
              :if={@end_of_list? && @page > 1}
              class="text-center py-4 text-base-content/60 text-sm"
            >
              No more queries to load
            </div>
          </div>
          
    <!-- Detail Panel -->
          <%= if @selected_question do %>
            <.question_detail question={@selected_question} findings={@question_findings} />
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
      {"open", "Open"},
      {"answered", "Answered"},
      {"abandoned", "Abandoned"},
      {"all", "All"}
    ]
  end

  attr(:id, :string, required: true)
  attr(:question, :map, required: true)
  attr(:selected, :boolean, default: false)

  defp question_card(assigns) do
    ~H"""
    <.link
      id={@id}
      patch={~p"/questions/#{@question.id}"}
      class={[
        "block bg-base-200 border rounded-lg p-4 transition-colors cursor-pointer",
        @selected && "border-secondary bg-base-300",
        !@selected && "border-base-300 hover:border-secondary/50 hover:bg-base-300/50"
      ]}
    >
      <div class="flex items-start justify-between gap-3">
        <p class="text-sm line-clamp-2 flex-1">{@question.question}</p>
        <span class={["badge", status_badge_class(@question.status)]}>
          {@question.status}
        </span>
      </div>
      <div class="flex items-center gap-2 mt-3">
        <div class="tooltip" data-tip="Priority level">
          <span class="badge badge-warning badge-sm">P:{@question.priority}</span>
        </div>
        <span class="badge badge-ghost badge-sm">x{@question.times_asked}</span>
        <%= if @question.cluster_id do %>
          <span class="badge badge-accent badge-sm">Clustered</span>
        <% end %>
      </div>
    </.link>
    """
  end

  attr(:question, :map, required: true)
  attr(:findings, :list, required: true)

  defp question_detail(assigns) do
    ~H"""
    <div class="flex-1 lg:max-w-lg">
      <div class="bg-base-200 border border-base-300 rounded-lg sticky top-20">
        <!-- Header -->
        <div class="flex items-center justify-between px-4 py-3 border-b border-base-300">
          <h3 class="text-sm font-semibold flex items-center gap-2">
            <.icon name="hero-magnifying-glass" class="w-4 h-4 text-secondary" /> Query Analysis
          </h3>
          <button
            phx-click="close_detail"
            class="btn btn-ghost btn-sm btn-square hover:btn-error"
          >
            <.icon name="hero-x-mark" class="w-4 h-4" />
          </button>
        </div>

        <div class="p-4 space-y-4">
          <!-- Question Text -->
          <div>
            <label class="text-xs uppercase tracking-wider text-base-content/50">
              Query
            </label>
            <p class="mt-1 text-lg">{@question.question}</p>
          </div>
          
    <!-- Context -->
          <%= if @question.context do %>
            <div>
              <label class="text-xs uppercase tracking-wider text-base-content/50">
                Context
              </label>
              <p class="mt-1 text-sm text-base-content/80">{@question.context}</p>
            </div>
          <% end %>
          
    <!-- Stats -->
          <div class="grid grid-cols-2 gap-3">
            <div class="bg-base-300 rounded-lg p-3">
              <div class="text-xs uppercase text-base-content/60">Priority</div>
              <div class="text-xl font-semibold text-warning mt-1">
                {@question.priority}<span class="text-base text-base-content/30">/10</span>
              </div>
            </div>
            <div class="bg-base-300 rounded-lg p-3">
              <div class="text-xs uppercase text-base-content/60">Times Asked</div>
              <div class="text-xl font-semibold mt-1">{@question.times_asked}</div>
            </div>
          </div>
          
    <!-- Metadata -->
          <div class="divider text-xs uppercase text-base-content/40">Details</div>

          <div class="space-y-2">
            <div class="flex items-center justify-between">
              <span class="text-xs text-base-content/50 uppercase">Status</span>
              <span class={["badge badge-sm", status_badge_class(@question.status)]}>
                {@question.status}
              </span>
            </div>
            <div class="flex items-center justify-between">
              <span class="text-xs text-base-content/50 uppercase">Last Asked</span>
              <span class="text-xs text-base-content/60">
                {format_datetime(@question.last_asked_at)}
              </span>
            </div>
            <%= if @question.resolved_at do %>
              <div class="flex items-center justify-between">
                <span class="text-xs text-base-content/50 uppercase">Resolved</span>
                <span class="text-xs text-success">
                  {format_datetime(@question.resolved_at)}
                </span>
              </div>
            <% end %>
            <div class="flex items-center justify-between">
              <span class="text-xs text-base-content/50 uppercase">Created</span>
              <span class="text-xs text-base-content/60">
                {format_datetime(@question.inserted_at)}
              </span>
            </div>
          </div>
          
    <!-- Findings -->
          <%= if @findings != [] do %>
            <div class="divider text-xs uppercase text-base-content/40">
              Findings ({length(@findings)})
            </div>

            <div class="space-y-2">
              <div
                :for={finding <- @findings}
                class="bg-base-300 border border-base-content/10 rounded-lg p-3"
              >
                <div class="flex items-start justify-between gap-2">
                  <p class="text-sm line-clamp-3">{truncate(finding.answer, 150)}</p>
                  <span class={["badge badge-xs shrink-0", finding_badge_class(finding.source_type)]}>
                    {finding.source_type}
                  </span>
                </div>
                <div class="flex items-center gap-2 mt-2">
                  <span class="text-xs text-base-content/50">
                    Conf: {Float.round(finding.confidence * 100, 0)}%
                  </span>
                  <%= if finding.verified do %>
                    <span class="badge badge-success badge-xs">
                      <.icon name="hero-check" class="w-3 h-3" /> Verified
                    </span>
                  <% end %>
                </div>
              </div>
            </div>
          <% end %>
          
    <!-- Actions -->
          <%= if @question.status == "open" do %>
            <div class="divider"></div>
            <button
              phx-click="abandon"
              phx-value-id={@question.id}
              data-confirm="Abandon this query? This cannot be undone."
              class="btn btn-error btn-outline btn-sm w-full"
            >
              <.icon name="hero-archive-box-x-mark" class="w-4 h-4" /> Abandon Query
            </button>
          <% end %>
        </div>
      </div>
    </div>
    """
  end

  # Style helpers
  defp status_badge_class("open"), do: "badge-secondary"
  defp status_badge_class("answered"), do: "badge-success"
  defp status_badge_class("abandoned"), do: "badge-warning"
  defp status_badge_class("merged"), do: "badge-info"
  defp status_badge_class(_), do: "badge-ghost"

  defp finding_badge_class("investigation"), do: "badge-info"
  defp finding_badge_class("serendipity"), do: "badge-accent"
  defp finding_badge_class("testimony"), do: "badge-secondary"
  defp finding_badge_class("inference"), do: "badge-warning"
  defp finding_badge_class(_), do: "badge-ghost"

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
