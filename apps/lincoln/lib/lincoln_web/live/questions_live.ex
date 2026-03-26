defmodule LincolnWeb.QuestionsLive do
  @moduledoc """
  LiveView for the Query Terminal - viewing and managing questions.
  Uses daisyUI tabs, cards, badges, and modal components.
  """
  use LincolnWeb, :live_view

  alias Lincoln.{Agents, Questions}

  @impl true
  def mount(_params, _session, socket) do
    {:ok, agent} = Agents.get_or_create_default_agent()

    socket =
      socket
      |> assign(:agent, agent)
      |> assign(:page_title, "Query Terminal")
      |> assign(:filter, "open")
      |> load_questions()

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

    {:noreply, socket}
  end

  def handle_params(_params, _uri, socket) do
    socket =
      socket
      |> assign(:selected_question, nil)
      |> assign(:question_findings, [])

    {:noreply, socket}
  end

  @impl true
  def handle_event("filter", %{"filter" => filter}, socket) do
    socket =
      socket
      |> assign(:filter, filter)
      |> load_questions()

    {:noreply, socket}
  end

  def handle_event("close_detail", _params, socket) do
    {:noreply, push_patch(socket, to: ~p"/questions")}
  end

  def handle_event("abandon", %{"id" => id}, socket) do
    question = Questions.get_question!(id)
    {:ok, _} = Questions.abandon_question(question)

    socket =
      socket
      |> load_questions()
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

  defp load_questions(socket) do
    agent = socket.assigns.agent
    filter = socket.assigns.filter

    questions =
      case filter do
        "open" ->
          Questions.list_open_questions(agent, limit: 50)

        "answered" ->
          Questions.list_questions(agent, status: "answered", limit: 50)

        "abandoned" ->
          Questions.list_questions(agent, status: "abandoned", limit: 50)

        _ ->
          Questions.list_questions(agent, limit: 50)
      end

    stream(socket, :questions, questions, reset: true)
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
              <.icon name="hero-question-mark-circle" class="size-6 text-secondary" /> Query Terminal
            </h1>
            <p class="text-sm font-terminal text-base-content/60 mt-1">
              Active investigations by {@agent.name}
            </p>
          </div>
          <a href="/" class="btn btn-outline btn-secondary btn-sm font-terminal uppercase">
            <.icon name="hero-arrow-left" class="size-4" /> Dashboard
          </a>
        </div>
        
    <!-- Filter Tabs -->
        <div role="tablist" class="tabs tabs-boxed bg-base-200 border-2 border-secondary w-fit">
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
          <!-- Questions List -->
          <div class={["flex-1", @selected_question && "lg:max-w-md"]}>
            <div id="questions-list" phx-update="stream" class="space-y-3">
              <!-- Empty state -->
              <div class="hidden only:flex flex-col items-center justify-center p-12 border-2 border-dashed border-base-content/20">
                <.icon name="hero-question-mark-circle" class="size-12 text-base-content/20 mb-3" />
                <p class="font-terminal text-sm uppercase text-base-content/40">
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
        "card bg-base-200 border-2 hover-lift transition-all cursor-pointer",
        @selected && "border-secondary bg-base-300 shadow-brutal",
        !@selected && "border-secondary/30 hover:border-secondary"
      ]}
    >
      <div class="card-body p-4">
        <div class="flex items-start justify-between gap-3">
          <p class="text-sm font-terminal line-clamp-2 flex-1">{@question.question}</p>
          <span class={[
            "badge font-terminal font-bold uppercase",
            status_badge_class(@question.status)
          ]}>
            {@question.status}
          </span>
        </div>
        <div class="card-actions justify-start mt-2">
          <div class="tooltip" data-tip="Priority level">
            <span class="badge badge-warning badge-sm font-terminal">P:{@question.priority}</span>
          </div>
          <span class="badge badge-ghost badge-sm font-terminal">x{@question.times_asked}</span>
          <%= if @question.cluster_id do %>
            <span class="badge badge-accent badge-sm font-terminal uppercase">Clustered</span>
          <% end %>
        </div>
      </div>
    </.link>
    """
  end

  attr(:question, :map, required: true)
  attr(:findings, :list, required: true)

  defp question_detail(assigns) do
    ~H"""
    <div class="flex-1 lg:max-w-lg">
      <div class="card bg-base-200 border-2 border-secondary sticky top-20">
        <!-- Header -->
        <div class="flex items-center justify-between px-4 py-3 border-b-2 border-secondary bg-base-300">
          <h3 class="font-terminal text-sm font-bold uppercase tracking-wider flex items-center gap-2">
            <.icon name="hero-magnifying-glass" class="size-4 text-secondary" /> Query Analysis
          </h3>
          <button
            phx-click="close_detail"
            class="btn btn-ghost btn-sm btn-square hover:btn-error"
          >
            <.icon name="hero-x-mark" class="size-4" />
          </button>
        </div>

        <div class="card-body p-4 space-y-4">
          <!-- Question Text -->
          <div>
            <label class="text-xs font-terminal uppercase tracking-wider text-base-content/50">
              Query
            </label>
            <p class="mt-1 font-terminal text-lg">{@question.question}</p>
          </div>
          
    <!-- Context -->
          <%= if @question.context do %>
            <div>
              <label class="text-xs font-terminal uppercase tracking-wider text-base-content/50">
                Context
              </label>
              <p class="mt-1 text-sm font-terminal text-base-content/80">{@question.context}</p>
            </div>
          <% end %>
          
    <!-- Stats -->
          <div class="stats stats-vertical sm:stats-horizontal bg-base-300 border border-secondary/30 w-full">
            <div class="stat p-3">
              <div class="stat-title text-xs font-terminal uppercase">Priority</div>
              <div class="stat-value text-xl font-terminal text-warning">
                {@question.priority}<span class="text-base text-base-content/30">/10</span>
              </div>
            </div>
            <div class="stat p-3">
              <div class="stat-title text-xs font-terminal uppercase">Times Asked</div>
              <div class="stat-value text-xl font-terminal">{@question.times_asked}</div>
            </div>
          </div>
          
    <!-- Metadata -->
          <div class="divider text-xs font-terminal uppercase text-base-content/40">Details</div>

          <div class="space-y-2">
            <div class="flex items-center justify-between">
              <span class="text-xs font-terminal text-base-content/50 uppercase">Status</span>
              <span class={[
                "badge badge-sm font-terminal uppercase",
                status_badge_class(@question.status)
              ]}>
                {@question.status}
              </span>
            </div>
            <div class="flex items-center justify-between">
              <span class="text-xs font-terminal text-base-content/50 uppercase">Last Asked</span>
              <span class="font-terminal text-xs text-base-content/60">
                {format_datetime(@question.last_asked_at)}
              </span>
            </div>
            <%= if @question.resolved_at do %>
              <div class="flex items-center justify-between">
                <span class="text-xs font-terminal text-base-content/50 uppercase">Resolved</span>
                <span class="font-terminal text-xs text-success">
                  {format_datetime(@question.resolved_at)}
                </span>
              </div>
            <% end %>
            <div class="flex items-center justify-between">
              <span class="text-xs font-terminal text-base-content/50 uppercase">Created</span>
              <span class="font-terminal text-xs text-base-content/60">
                {format_datetime(@question.inserted_at)}
              </span>
            </div>
          </div>
          
    <!-- Findings -->
          <%= if @findings != [] do %>
            <div class="divider text-xs font-terminal uppercase text-base-content/40">
              Findings ({length(@findings)})
            </div>

            <div class="space-y-2">
              <div
                :for={finding <- @findings}
                class="card bg-base-300 border border-accent/30"
              >
                <div class="card-body p-3">
                  <div class="flex items-start justify-between gap-2">
                    <p class="text-sm font-terminal line-clamp-3">{truncate(finding.answer, 150)}</p>
                    <span class={[
                      "badge badge-xs font-terminal uppercase shrink-0",
                      finding_badge_class(finding.source_type)
                    ]}>
                      {finding.source_type}
                    </span>
                  </div>
                  <div class="flex items-center gap-2 mt-2">
                    <span class="text-xs font-terminal text-base-content/50">
                      Conf: {Float.round(finding.confidence * 100, 0)}%
                    </span>
                    <%= if finding.verified do %>
                      <span class="badge badge-success badge-xs font-terminal uppercase">
                        <.icon name="hero-check" class="size-3" /> Verified
                      </span>
                    <% end %>
                  </div>
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
              class="btn btn-error btn-outline btn-sm w-full font-terminal uppercase"
            >
              <.icon name="hero-archive-box-x-mark" class="size-4" /> Abandon Query
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
