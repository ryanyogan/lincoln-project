defmodule LincolnWeb.DashboardLive do
  @moduledoc """
  Main dashboard for Lincoln agents - Neural Command Center.

  Shows:
  - Agent overview and stats
  - Recent beliefs and their confidence levels
  - Open questions
  - Recent memories
  - Activity timeline
  """
  use LincolnWeb, :live_view

  alias Lincoln.Adapters.LLM
  alias Lincoln.{Agents, Beliefs, Memory, Questions}

  @impl true
  def mount(_params, _session, socket) do
    # Get or create the default agent
    {:ok, agent} = Agents.get_or_create_default_agent()

    socket =
      socket
      |> assign(:agent, agent)
      |> assign(:page_title, "Neural Command Center")
      |> assign(:llm_status, :unknown)
      |> assign(:llm_latency, nil)
      |> assign(:llm_error, nil)
      |> assign(:llm_testing, false)
      |> assign(:embeddings_status, :unknown)
      |> assign(:embeddings_latency, nil)
      |> assign(:embeddings_error, nil)
      |> assign(:embeddings_testing, false)
      |> load_dashboard_data()

    # Subscribe to updates if connected
    if connected?(socket) do
      Phoenix.PubSub.subscribe(Lincoln.PubSub, "agent:#{agent.id}")
    end

    {:ok, socket}
  end

  @impl true
  def handle_params(_params, _uri, socket) do
    {:noreply, socket}
  end

  # ============================================================================
  # Event Handlers
  # ============================================================================

  @impl true
  def handle_event("test_llm", _params, socket) do
    # Start testing
    socket = assign(socket, :llm_testing, true)

    # Run the test asynchronously
    send(self(), :run_llm_test)

    {:noreply, socket}
  end

  def handle_event("test_embeddings", _params, socket) do
    socket = assign(socket, :embeddings_testing, true)
    send(self(), :run_embeddings_test)
    {:noreply, socket}
  end

  # ============================================================================
  # PubSub Handlers for Real-time Updates
  # ============================================================================

  @impl true
  def handle_info({:belief_created, _belief}, socket) do
    {:noreply, load_dashboard_data(socket)}
  end

  def handle_info({:belief_updated, _belief}, socket) do
    {:noreply, load_dashboard_data(socket)}
  end

  def handle_info({:belief_revised, _belief, _revision}, socket) do
    {:noreply, load_dashboard_data(socket)}
  end

  def handle_info({:question_created, _question}, socket) do
    {:noreply, load_dashboard_data(socket)}
  end

  def handle_info({:question_updated, _question}, socket) do
    {:noreply, load_dashboard_data(socket)}
  end

  def handle_info({:question_resolved, _question, _finding}, socket) do
    {:noreply, load_dashboard_data(socket)}
  end

  def handle_info({:finding_created, _finding}, socket) do
    {:noreply, load_dashboard_data(socket)}
  end

  def handle_info({:memory_created, _memory}, socket) do
    {:noreply, load_dashboard_data(socket)}
  end

  def handle_info({:memory_updated, _memory}, socket) do
    {:noreply, load_dashboard_data(socket)}
  end

  def handle_info({:action_logged, _action}, socket) do
    {:noreply, load_dashboard_data(socket)}
  end

  def handle_info({:action_completed, _action}, socket) do
    {:noreply, load_dashboard_data(socket)}
  end

  # System status test handlers
  def handle_info(:run_llm_test, socket) do
    start_time = System.monotonic_time(:millisecond)

    result =
      try do
        LLM.Anthropic.complete(
          "Respond with exactly: OK",
          system: "You are a system health check. Respond precisely as instructed."
        )
      rescue
        e -> {:error, {:exception, Exception.message(e)}}
      end

    elapsed = System.monotonic_time(:millisecond) - start_time

    socket =
      case result do
        {:ok, _response} ->
          socket
          |> assign(:llm_status, :connected)
          |> assign(:llm_latency, elapsed)
          |> assign(:llm_error, nil)

        {:error, {:api_error, 401, _}} ->
          socket
          |> assign(:llm_status, :error)
          |> assign(:llm_error, "Invalid API key")

        {:error, {:api_error, 429, _}} ->
          socket
          |> assign(:llm_status, :error)
          |> assign(:llm_error, "Rate limited")

        {:error, {:api_error, status, _}} ->
          socket
          |> assign(:llm_status, :error)
          |> assign(:llm_error, "API error (#{status})")

        {:error, {:request_failed, _reason}} ->
          socket
          |> assign(:llm_status, :error)
          |> assign(:llm_error, "Connection failed")

        {:error, reason} ->
          socket
          |> assign(:llm_status, :error)
          |> assign(:llm_error, inspect(reason))
      end

    {:noreply, assign(socket, :llm_testing, false)}
  end

  def handle_info(:run_embeddings_test, socket) do
    start_time = System.monotonic_time(:millisecond)
    embeddings = Lincoln.Cognition.embeddings_adapter()

    result =
      try do
        embeddings.embed("health check test")
      rescue
        e -> {:error, {:exception, Exception.message(e)}}
      end

    elapsed = System.monotonic_time(:millisecond) - start_time

    socket =
      case result do
        {:ok, embedding} when is_list(embedding) ->
          socket
          |> assign(:embeddings_status, :connected)
          |> assign(:embeddings_latency, elapsed)
          |> assign(:embeddings_error, nil)

        {:error, {:service_error, status, _}} ->
          socket
          |> assign(:embeddings_status, :error)
          |> assign(:embeddings_error, "Service error (#{status})")

        {:error, {:request_failed, _}} ->
          socket
          |> assign(:embeddings_status, :error)
          |> assign(:embeddings_error, "Connection failed - is ML service running?")

        {:error, reason} ->
          socket
          |> assign(:embeddings_status, :error)
          |> assign(:embeddings_error, inspect(reason))
      end

    {:noreply, assign(socket, :embeddings_testing, false)}
  end

  # Catch-all for any other messages
  def handle_info(_msg, socket) do
    {:noreply, socket}
  end

  # ============================================================================
  # Private Helpers
  # ============================================================================

  defp load_dashboard_data(socket) do
    agent = socket.assigns.agent

    socket
    |> assign(:beliefs, Beliefs.list_beliefs(agent) |> Enum.take(8))
    |> assign(:open_questions, Questions.list_open_questions(agent, limit: 8))
    |> assign(:recent_memories, Memory.list_recent_memories(agent, 24, limit: 8))
    |> assign(:recent_actions, Questions.list_recent_actions(agent, 24, limit: 8))
    |> assign(:stats, calculate_stats(agent))
  end

  defp calculate_stats(agent) do
    %{
      beliefs_count: agent.beliefs_count,
      memories_count: agent.memories_count,
      questions_count: agent.questions_asked_count,
      open_questions: length(Questions.list_open_questions(agent, limit: 100))
    }
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash}>
      <div class="space-y-6">
        <%!-- Agent Header --%>
        <div class="bg-base-200 border-2 border-primary p-4 sm:p-6 shadow-brutal scan-lines">
          <div class="flex flex-col sm:flex-row items-start sm:items-center gap-4">
            <div class="w-16 sm:w-20 h-16 sm:h-20 bg-primary text-primary-content flex items-center justify-center border-2 border-primary shadow-brutal">
              <span class="text-3xl sm:text-4xl font-black font-terminal">L</span>
            </div>
            <div class="flex-1">
              <h1 class="text-2xl sm:text-3xl font-black font-terminal uppercase tracking-tight">
                {@agent.name}
              </h1>
              <p class="text-base-content/50 font-terminal text-sm mt-1">
                {@agent.description || "Persistent Learning Agent"}
              </p>
              <div class="flex items-center gap-2 mt-2">
                <.badge type={:success}>{@agent.status}</.badge>
                <.badge type={:accent}>Learning Mode</.badge>
              </div>
            </div>
            <div class="hidden lg:flex gap-3">
              <.stat_card title="Uptime" value="Active" class="min-w-24" />
              <.stat_card title="Mode" value="Learning" class="min-w-24" />
            </div>
          </div>
        </div>

        <%!-- Stats Grid --%>
        <div class="stats stats-vertical sm:stats-horizontal bg-base-200 w-full border-2 border-primary shadow-brutal-primary">
          <div class="stat">
            <div class="stat-figure text-primary">
              <.icon name="hero-light-bulb" class="size-6" />
            </div>
            <div class="stat-title font-terminal uppercase text-[10px] tracking-widest">Beliefs</div>
            <div class="stat-value text-primary font-terminal">{@stats.beliefs_count}</div>
            <div class="stat-desc font-terminal text-xs">Knowledge structures</div>
          </div>
          <div class="stat">
            <div class="stat-figure text-secondary">
              <.icon name="hero-archive-box" class="size-6" />
            </div>
            <div class="stat-title font-terminal uppercase text-[10px] tracking-widest">Memories</div>
            <div class="stat-value text-secondary font-terminal">{@stats.memories_count}</div>
            <div class="stat-desc font-terminal text-xs">Experience stored</div>
          </div>
          <div class="stat">
            <div class="stat-figure text-accent">
              <.icon name="hero-question-mark-circle" class="size-6" />
            </div>
            <div class="stat-title font-terminal uppercase text-[10px] tracking-widest">
              Questions
            </div>
            <div class="stat-value text-accent font-terminal">{@stats.questions_count}</div>
            <div class="stat-desc font-terminal text-xs">Total asked</div>
          </div>
          <div class="stat">
            <div class="stat-figure text-warning">
              <.icon name="hero-magnifying-glass" class="size-6" />
            </div>
            <div class="stat-title font-terminal uppercase text-[10px] tracking-widest">Open</div>
            <div class="stat-value text-warning font-terminal">{@stats.open_questions}</div>
            <div class="stat-desc font-terminal text-xs">Under investigation</div>
          </div>
        </div>

        <%!-- System Status --%>
        <.card variant={:info}>
          <:header>
            <span class="flex items-center gap-2">
              <.icon name="hero-server-stack" class="size-4 text-info" /> System Status
            </span>
          </:header>
          <div class="grid sm:grid-cols-2 gap-4">
            <.system_status_row
              name="Claude API"
              status={@llm_status}
              testing={@llm_testing}
              latency={@llm_latency}
              error={@llm_error}
              test_event="test_llm"
              border_color="border-primary/30"
            />
            <.system_status_row
              name="ML Service"
              status={@embeddings_status}
              testing={@embeddings_testing}
              latency={@embeddings_latency}
              error={@embeddings_error}
              test_event="test_embeddings"
              border_color="border-secondary/30"
            />
          </div>
        </.card>

        <%!-- Main Content Grid --%>
        <div class="grid lg:grid-cols-2 gap-6">
          <.data_card
            title="Belief Matrix"
            icon="hero-light-bulb"
            icon_color="text-primary"
            border_color="border-primary/40"
            view_all_path={~p"/beliefs"}
          >
            <%= if @beliefs == [] do %>
              <.empty_state icon="hero-light-bulb" title="No beliefs formed yet" />
            <% else %>
              <ul class="space-y-2">
                <li :for={belief <- @beliefs}><.belief_row belief={belief} /></li>
              </ul>
            <% end %>
          </.data_card>

          <.data_card
            title="Active Queries"
            icon="hero-question-mark-circle"
            icon_color="text-secondary"
            border_color="border-secondary/40"
            view_all_path={~p"/questions"}
          >
            <%= if @open_questions == [] do %>
              <.empty_state icon="hero-question-mark-circle" title="No open questions" />
            <% else %>
              <ul class="space-y-2">
                <li :for={question <- @open_questions}><.question_row question={question} /></li>
              </ul>
            <% end %>
          </.data_card>

          <.data_card
            title="Memory Bank"
            icon="hero-archive-box"
            icon_color="text-accent"
            border_color="border-accent/40"
            view_all_path={~p"/memories"}
          >
            <%= if @recent_memories == [] do %>
              <.empty_state icon="hero-archive-box" title="No memories recorded" />
            <% else %>
              <ul class="space-y-2">
                <li :for={memory <- @recent_memories}><.memory_row memory={memory} /></li>
              </ul>
            <% end %>
          </.data_card>

          <.data_card
            title="Activity Log"
            icon="hero-clock"
            icon_color="text-info"
            border_color="border-info/40"
          >
            <%= if @recent_actions == [] do %>
              <.empty_state icon="hero-clock" title="No recent activity" />
            <% else %>
              <ul class="timeline timeline-vertical timeline-compact">
                <li :for={action <- @recent_actions}><.timeline_item action={action} /></li>
              </ul>
            <% end %>
          </.data_card>
        </div>
      </div>
    </Layouts.app>
    """
  end

  # ============================================================================
  # Component Functions
  # ============================================================================

  attr(:name, :string, required: true)
  attr(:status, :atom, required: true)
  attr(:testing, :boolean, required: true)
  attr(:latency, :any, default: nil)
  attr(:error, :string, default: nil)
  attr(:test_event, :string, required: true)
  attr(:border_color, :string, default: "border-base-300")

  defp system_status_row(assigns) do
    ~H"""
    <div class={["flex items-center justify-between p-3 bg-base-300 border-2", @border_color]}>
      <div class="flex items-center gap-3">
        <.status_indicator
          status={status_to_indicator(@status)}
          pulse={@status == :connected}
          size={:lg}
        />
        <div>
          <p class="font-terminal text-sm font-bold">{@name}</p>
          <p class="font-terminal text-xs text-base-content/50">
            <%= cond do %>
              <% @testing -> %>
                Testing...
              <% @status == :connected -> %>
                Connected ({@latency}ms)
              <% @status == :error -> %>
                <span class="text-error">{@error}</span>
              <% true -> %>
                Not tested
            <% end %>
          </p>
        </div>
      </div>
      <button
        phx-click={@test_event}
        disabled={@testing}
        class="btn btn-sm btn-outline font-terminal border-2"
      >
        <%= if @testing do %>
          <span class="loading loading-spinner loading-xs"></span>
        <% else %>
          Test
        <% end %>
      </button>
    </div>
    """
  end

  defp status_to_indicator(:connected), do: :online
  defp status_to_indicator(:error), do: :error
  defp status_to_indicator(_), do: :idle

  attr(:belief, :map, required: true)

  defp belief_row(assigns) do
    ~H"""
    <.link
      navigate={~p"/beliefs/#{@belief.id}"}
      class="block p-3 bg-base-300 border-2 border-primary/20 hover:border-primary hover-lift transition-all"
    >
      <div class="flex items-start justify-between gap-2">
        <p class="text-sm font-terminal line-clamp-2">{@belief.statement}</p>
        <.badge type={confidence_badge_type(@belief.confidence)}>
          {Float.round(@belief.confidence * 100, 0)}%
        </.badge>
      </div>
      <div class="flex items-center gap-2 mt-2">
        <.badge type={source_badge_type(@belief.source_type)}>{@belief.source_type}</.badge>
        <span class="text-[10px] font-terminal text-base-content/40">E:{@belief.entrenchment}</span>
      </div>
    </.link>
    """
  end

  attr(:question, :map, required: true)

  defp question_row(assigns) do
    ~H"""
    <.link
      navigate={~p"/questions/#{@question.id}"}
      class="block p-3 bg-base-300 border-2 border-secondary/20 hover:border-secondary hover-lift transition-all"
    >
      <p class="text-sm font-terminal line-clamp-2">{@question.question}</p>
      <div class="flex items-center gap-2 mt-2">
        <.badge type={:warning}>P:{@question.priority}</.badge>
        <span class="text-[10px] font-terminal text-base-content/40">x{@question.times_asked}</span>
      </div>
    </.link>
    """
  end

  attr(:memory, :map, required: true)

  defp memory_row(assigns) do
    ~H"""
    <.link
      navigate={~p"/memories/#{@memory.id}"}
      class="block p-3 bg-base-300 border-2 border-accent/20 hover:border-accent hover-lift transition-all"
    >
      <p class="text-sm font-terminal line-clamp-2">{truncate(@memory.content, 100)}</p>
      <div class="flex items-center gap-2 mt-2">
        <.badge type={memory_badge_type(@memory.memory_type)}>{@memory.memory_type}</.badge>
        <.importance_dots importance={@memory.importance} />
      </div>
    </.link>
    """
  end

  attr(:action, :map, required: true)

  defp timeline_item(assigns) do
    ~H"""
    <div class="timeline-start timeline-box bg-base-300 border-2 border-info/20 p-2">
      <div class="flex items-center gap-2">
        <.badge type={:info}>{@action.action_type}</.badge>
        <.badge type={outcome_badge_type(@action.outcome)}>{@action.outcome || "pending"}</.badge>
      </div>
      <%= if @action.description do %>
        <p class="text-xs font-terminal text-base-content/50 mt-1 line-clamp-1">
          {truncate(@action.description, 60)}
        </p>
      <% end %>
    </div>
    <div class="timeline-middle">
      <span class="status-dot status-dot-online"></span>
    </div>
    <hr class="bg-info/30" />
    """
  end

  attr(:importance, :integer, required: true)

  defp importance_dots(assigns) do
    ~H"""
    <div class="flex items-center gap-0.5" title={"Importance: #{@importance}/10"}>
      <span
        :for={i <- 1..5}
        class={[
          "w-1.5 h-2",
          i <= div(@importance, 2) && "bg-accent",
          i > div(@importance, 2) && "bg-base-content/20"
        ]}
      />
    </div>
    """
  end

  # Style helpers — return badge type atoms for <.badge> component
  defp confidence_badge_type(conf) when conf >= 0.8, do: :success
  defp confidence_badge_type(conf) when conf >= 0.5, do: :warning
  defp confidence_badge_type(_), do: :error

  defp source_badge_type("observation"), do: :info
  defp source_badge_type("inference"), do: :secondary
  defp source_badge_type("training"), do: :warning
  defp source_badge_type("testimony"), do: :accent
  defp source_badge_type(_), do: :default

  defp memory_badge_type("observation"), do: :info
  defp memory_badge_type("reflection"), do: :secondary
  defp memory_badge_type("conversation"), do: :accent
  defp memory_badge_type("plan"), do: :primary
  defp memory_badge_type(_), do: :default

  defp outcome_badge_type("success"), do: :success
  defp outcome_badge_type("failure"), do: :error
  defp outcome_badge_type(_), do: :default

  defp truncate(text, max_length) when is_binary(text) do
    if String.length(text) > max_length do
      String.slice(text, 0, max_length) <> "..."
    else
      text
    end
  end

  defp truncate(_, _), do: ""
end
