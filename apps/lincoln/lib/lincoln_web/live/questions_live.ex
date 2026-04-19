defmodule LincolnWeb.QuestionsLive do
  @moduledoc """
  LiveView for the Query Terminal - viewing and managing questions.
  Uses neobrutalist core components (page_header, filter_tabs, badge, etc).
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
        <.page_header
          title="Query Terminal"
          subtitle={"Active investigations by #{@agent.name}"}
          icon="hero-question-mark-circle"
          icon_color="text-secondary"
        >
          <:actions>
            <.link
              navigate={~p"/"}
              class="btn btn-ghost btn-sm font-terminal uppercase border-2 border-base-300 hover:border-primary"
            >
              <.icon name="hero-arrow-left" class="w-4 h-4" /> Dashboard
            </.link>
          </:actions>
        </.page_header>
        
    <!-- Filter Tabs -->
        <.filter_tabs options={filter_options()} active={@filter} />
        
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
              <div class="hidden only:flex">
                <.empty_state
                  icon="hero-question-mark-circle"
                  title="No queries"
                  description="No queries match this filter"
                />
              </div>
              <!-- Question cards -->
              <.question_card
                :for={{dom_id, question} <- @streams.questions}
                id={dom_id}
                question={question}
                selected={@selected_question && @selected_question.id == question.id}
              />
            </div>
            <.load_more end_of_list?={@end_of_list?} />
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
        "block bg-base-200 border-2 p-4 transition-all cursor-pointer hover-lift",
        @selected && "border-primary shadow-brutal-sm bg-base-300",
        !@selected && "border-base-300 hover:border-primary/50 hover:bg-base-300/50"
      ]}
    >
      <div class="flex items-start justify-between gap-3">
        <p class="text-sm font-terminal line-clamp-2 flex-1">{@question.question}</p>
        <.badge type={status_badge_type(@question.status)}>
          {@question.status}
        </.badge>
      </div>
      <div class="flex items-center gap-2 mt-3">
        <div class="tooltip" data-tip="Priority level">
          <.badge type={:warning}>P:{@question.priority}</.badge>
        </div>
        <.badge type={:default}>x{@question.times_asked}</.badge>
        <%= if @question.cluster_id do %>
          <.badge type={:accent}>Clustered</.badge>
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
      <div class="bg-base-200 border-2 border-base-300 shadow-brutal sticky top-20">
        <!-- Header -->
        <div class="flex items-center justify-between px-4 py-3 border-b-2 border-base-300">
          <h3 class="text-sm font-terminal font-bold uppercase tracking-wide flex items-center gap-2">
            <.icon name="hero-magnifying-glass" class="w-4 h-4 text-secondary" /> Query Analysis
          </h3>
          <button
            phx-click="close_detail"
            class="btn btn-ghost btn-sm btn-square hover:btn-error border-2 border-transparent hover:border-error"
          >
            <.icon name="hero-x-mark" class="w-4 h-4" />
          </button>
        </div>

        <div class="p-4 space-y-4">
          <!-- Question Text -->
          <div>
            <label class="text-[10px] font-terminal uppercase tracking-widest text-base-content/40">
              Query
            </label>
            <p class="mt-1 text-lg font-terminal">{@question.question}</p>
          </div>
          
    <!-- Context -->
          <%= if @question.context do %>
            <div>
              <label class="text-[10px] font-terminal uppercase tracking-widest text-base-content/40">
                Context
              </label>
              <p class="mt-1 text-sm font-terminal text-base-content/80">{@question.context}</p>
            </div>
          <% end %>
          
    <!-- Stats -->
          <div class="grid grid-cols-2 gap-3">
            <div class="bg-base-300 border-2 border-base-content/10 p-3">
              <div class="text-[10px] font-terminal uppercase tracking-widest text-base-content/40">
                Priority
              </div>
              <div class="text-xl font-black font-terminal text-warning mt-1">
                {@question.priority}<span class="text-base text-base-content/30">/10</span>
              </div>
            </div>
            <div class="bg-base-300 border-2 border-base-content/10 p-3">
              <div class="text-[10px] font-terminal uppercase tracking-widest text-base-content/40">
                Times Asked
              </div>
              <div class="text-xl font-black font-terminal mt-1">{@question.times_asked}</div>
            </div>
          </div>
          
    <!-- Metadata -->
          <div class="divider text-[10px] font-terminal uppercase tracking-widest text-base-content/40">
            Details
          </div>

          <div class="space-y-2">
            <div class="flex items-center justify-between">
              <span class="text-[10px] font-terminal uppercase tracking-widest text-base-content/40">
                Status
              </span>
              <.badge type={status_badge_type(@question.status)}>
                {@question.status}
              </.badge>
            </div>
            <div class="flex items-center justify-between">
              <span class="text-[10px] font-terminal uppercase tracking-widest text-base-content/40">
                Last Asked
              </span>
              <span class="text-xs font-terminal text-base-content/60">
                {format_datetime(@question.last_asked_at)}
              </span>
            </div>
            <%= if @question.resolved_at do %>
              <div class="flex items-center justify-between">
                <span class="text-[10px] font-terminal uppercase tracking-widest text-base-content/40">
                  Resolved
                </span>
                <span class="text-xs font-terminal text-success">
                  {format_datetime(@question.resolved_at)}
                </span>
              </div>
            <% end %>
            <div class="flex items-center justify-between">
              <span class="text-[10px] font-terminal uppercase tracking-widest text-base-content/40">
                Created
              </span>
              <span class="text-xs font-terminal text-base-content/60">
                {format_datetime(@question.inserted_at)}
              </span>
            </div>
          </div>
          
    <!-- Findings -->
          <%= if @findings != [] do %>
            <div class="divider text-[10px] font-terminal uppercase tracking-widest text-base-content/40">
              Findings ({length(@findings)})
            </div>

            <div class="space-y-2">
              <div
                :for={finding <- @findings}
                class="bg-base-300 border-2 border-base-content/10 p-3 shadow-brutal-sm"
              >
                <div class="flex items-start justify-between gap-2">
                  <p class="text-sm font-terminal line-clamp-3">{truncate(finding.answer, 150)}</p>
                  <.badge type={finding_badge_type(finding.source_type)}>
                    {finding.source_type}
                  </.badge>
                </div>
                <div class="flex items-center gap-2 mt-2">
                  <span class="text-[10px] font-terminal uppercase tracking-widest text-base-content/40">
                    Conf: {Float.round(finding.confidence * 100, 0)}%
                  </span>
                  <%= if finding.verified do %>
                    <.badge type={:success}>
                      <.icon name="hero-check" class="w-3 h-3" /> Verified
                    </.badge>
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
              class="btn btn-error btn-outline btn-sm w-full font-terminal uppercase border-2 hover:shadow-brutal-sm"
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
  defp status_badge_type("open"), do: :secondary
  defp status_badge_type("answered"), do: :success
  defp status_badge_type("abandoned"), do: :warning
  defp status_badge_type("merged"), do: :info
  defp status_badge_type(_), do: :default

  defp finding_badge_type("investigation"), do: :info
  defp finding_badge_type("serendipity"), do: :accent
  defp finding_badge_type("testimony"), do: :secondary
  defp finding_badge_type("inference"), do: :warning
  defp finding_badge_type(_), do: :default

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
