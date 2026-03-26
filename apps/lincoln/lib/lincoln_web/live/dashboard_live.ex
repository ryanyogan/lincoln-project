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

  alias Lincoln.{Agents, Beliefs, Memory, Questions}
  alias Lincoln.Adapters.LLM

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
        <!-- Agent Header Card -->
        <div class="card bg-base-200 border-2 border-primary">
          <div class="card-body p-4 sm:p-6">
            <div class="flex flex-col sm:flex-row items-start sm:items-center gap-4">
              <!-- Agent Avatar -->
              <div class="avatar placeholder">
                <div class="bg-primary text-primary-content w-16 sm:w-20 border-2 border-primary shadow-brutal">
                  <span class="text-3xl sm:text-4xl font-black font-terminal">L</span>
                </div>
              </div>
              
    <!-- Agent Info -->
              <div class="flex-1">
                <h1 class="text-2xl sm:text-3xl font-black font-terminal uppercase tracking-tight">
                  {@agent.name}
                </h1>
                <p class="text-base-content/60 font-terminal text-sm mt-1">
                  {@agent.description || "Persistent Learning Agent"}
                </p>
                <div class="flex items-center gap-2 mt-2">
                  <span class="badge badge-accent gap-1">
                    <span class="status status-success"></span>
                    {@agent.status}
                  </span>
                  <span class="badge badge-outline badge-sm font-terminal">Learning Mode</span>
                </div>
              </div>
              
    <!-- Quick Stats (desktop) -->
              <div class="hidden lg:flex gap-2">
                <div class="stat bg-base-300 border border-primary/30 p-3">
                  <div class="stat-title text-xs font-terminal">Uptime</div>
                  <div class="stat-value text-primary text-lg font-terminal">Active</div>
                </div>
                <div class="stat bg-base-300 border border-primary/30 p-3">
                  <div class="stat-title text-xs font-terminal">Mode</div>
                  <div class="stat-value text-accent text-lg font-terminal">Learning</div>
                </div>
              </div>
            </div>
          </div>
        </div>
        
    <!-- Stats Grid using daisyUI stats component -->
        <div class="stats stats-vertical sm:stats-horizontal shadow-brutal-primary bg-base-200 w-full border-2 border-primary">
          <div class="stat">
            <div class="stat-figure text-primary">
              <.icon name="hero-light-bulb" class="size-8" />
            </div>
            <div class="stat-title font-terminal uppercase text-xs">Beliefs</div>
            <div class="stat-value text-primary font-terminal">{@stats.beliefs_count}</div>
            <div class="stat-desc font-terminal">Knowledge structures</div>
          </div>

          <div class="stat">
            <div class="stat-figure text-secondary">
              <.icon name="hero-archive-box" class="size-8" />
            </div>
            <div class="stat-title font-terminal uppercase text-xs">Memories</div>
            <div class="stat-value text-secondary font-terminal">{@stats.memories_count}</div>
            <div class="stat-desc font-terminal">Experience stored</div>
          </div>

          <div class="stat">
            <div class="stat-figure text-accent">
              <.icon name="hero-question-mark-circle" class="size-8" />
            </div>
            <div class="stat-title font-terminal uppercase text-xs">Questions</div>
            <div class="stat-value text-accent font-terminal">{@stats.questions_count}</div>
            <div class="stat-desc font-terminal">Total asked</div>
          </div>

          <div class="stat">
            <div class="stat-figure text-warning">
              <.icon name="hero-magnifying-glass" class="size-8" />
            </div>
            <div class="stat-title font-terminal uppercase text-xs">Open</div>
            <div class="stat-value text-warning font-terminal">{@stats.open_questions}</div>
            <div class="stat-desc font-terminal">Under investigation</div>
          </div>
        </div>
        
    <!-- System Status Card -->
        <div class="card bg-base-200 border-2 border-info">
          <div class="card-body p-4">
            <h2 class="card-title text-sm font-terminal uppercase gap-2 mb-3">
              <.icon name="hero-server-stack" class="size-4 text-info" /> System Status
            </h2>
            <div class="grid sm:grid-cols-2 gap-4">
              <!-- LLM Status -->
              <div class="flex items-center justify-between p-3 bg-base-300 border border-primary/30">
                <div class="flex items-center gap-3">
                  <div class={[
                    "w-3 h-3 rounded-full",
                    @llm_status == :connected && "bg-success animate-pulse",
                    @llm_status == :error && "bg-error",
                    @llm_status == :unknown && "bg-base-content/30"
                  ]}>
                  </div>
                  <div>
                    <p class="font-terminal text-sm font-bold">Claude API</p>
                    <p class="font-terminal text-xs text-base-content/60">
                      <%= cond do %>
                        <% @llm_testing -> %>
                          Testing...
                        <% @llm_status == :connected -> %>
                          Connected ({@llm_latency}ms)
                        <% @llm_status == :error -> %>
                          <span class="text-error">{@llm_error}</span>
                        <% true -> %>
                          Not tested
                      <% end %>
                    </p>
                  </div>
                </div>
                <button
                  phx-click="test_llm"
                  disabled={@llm_testing}
                  class={[
                    "btn btn-sm btn-outline btn-primary font-terminal",
                    @llm_testing && "loading"
                  ]}
                >
                  <%= if @llm_testing do %>
                    <span class="loading loading-spinner loading-xs"></span>
                  <% else %>
                    Test
                  <% end %>
                </button>
              </div>
              
    <!-- Embeddings Status -->
              <div class="flex items-center justify-between p-3 bg-base-300 border border-secondary/30">
                <div class="flex items-center gap-3">
                  <div class={[
                    "w-3 h-3 rounded-full",
                    @embeddings_status == :connected && "bg-success animate-pulse",
                    @embeddings_status == :error && "bg-error",
                    @embeddings_status == :unknown && "bg-base-content/30"
                  ]}>
                  </div>
                  <div>
                    <p class="font-terminal text-sm font-bold">ML Service</p>
                    <p class="font-terminal text-xs text-base-content/60">
                      <%= cond do %>
                        <% @embeddings_testing -> %>
                          Testing...
                        <% @embeddings_status == :connected -> %>
                          Connected ({@embeddings_latency}ms)
                        <% @embeddings_status == :error -> %>
                          <span class="text-error">{@embeddings_error}</span>
                        <% true -> %>
                          Not tested
                      <% end %>
                    </p>
                  </div>
                </div>
                <button
                  phx-click="test_embeddings"
                  disabled={@embeddings_testing}
                  class={[
                    "btn btn-sm btn-outline btn-secondary font-terminal",
                    @embeddings_testing && "loading"
                  ]}
                >
                  <%= if @embeddings_testing do %>
                    <span class="loading loading-spinner loading-xs"></span>
                  <% else %>
                    Test
                  <% end %>
                </button>
              </div>
            </div>
          </div>
        </div>
        
    <!-- Main Content Grid -->
        <div class="grid lg:grid-cols-2 gap-6">
          <!-- Beliefs Panel -->
          <div class="card bg-base-200 border-2 border-primary/50 hover:border-primary transition-colors">
            <div class="card-body p-0">
              <div class="flex items-center justify-between px-4 py-3 border-b-2 border-primary/30 bg-base-300">
                <h2 class="card-title text-sm font-terminal uppercase gap-2">
                  <.icon name="hero-light-bulb" class="size-4 text-primary" /> Belief Matrix
                </h2>
                <a href="/beliefs" class="btn btn-ghost btn-xs font-terminal">
                  View All <.icon name="hero-arrow-right" class="size-3" />
                </a>
              </div>
              <div class="p-4 max-h-80 overflow-y-auto">
                <%= if @beliefs == [] do %>
                  <.empty_state icon="hero-light-bulb" message="No beliefs formed yet" />
                <% else %>
                  <ul class="space-y-2">
                    <li :for={belief <- @beliefs}>
                      <.belief_row belief={belief} />
                    </li>
                  </ul>
                <% end %>
              </div>
            </div>
          </div>
          
    <!-- Questions Panel -->
          <div class="card bg-base-200 border-2 border-secondary/50 hover:border-secondary transition-colors">
            <div class="card-body p-0">
              <div class="flex items-center justify-between px-4 py-3 border-b-2 border-secondary/30 bg-base-300">
                <h2 class="card-title text-sm font-terminal uppercase gap-2">
                  <.icon name="hero-question-mark-circle" class="size-4 text-secondary" />
                  Active Queries
                </h2>
                <a href="/questions" class="btn btn-ghost btn-xs font-terminal">
                  View All <.icon name="hero-arrow-right" class="size-3" />
                </a>
              </div>
              <div class="p-4 max-h-80 overflow-y-auto">
                <%= if @open_questions == [] do %>
                  <.empty_state icon="hero-question-mark-circle" message="No open questions" />
                <% else %>
                  <ul class="space-y-2">
                    <li :for={question <- @open_questions}>
                      <.question_row question={question} />
                    </li>
                  </ul>
                <% end %>
              </div>
            </div>
          </div>
          
    <!-- Memories Panel -->
          <div class="card bg-base-200 border-2 border-accent/50 hover:border-accent transition-colors">
            <div class="card-body p-0">
              <div class="flex items-center justify-between px-4 py-3 border-b-2 border-accent/30 bg-base-300">
                <h2 class="card-title text-sm font-terminal uppercase gap-2">
                  <.icon name="hero-archive-box" class="size-4 text-accent" /> Memory Bank
                </h2>
                <a href="/memories" class="btn btn-ghost btn-xs font-terminal">
                  View All <.icon name="hero-arrow-right" class="size-3" />
                </a>
              </div>
              <div class="p-4 max-h-80 overflow-y-auto">
                <%= if @recent_memories == [] do %>
                  <.empty_state icon="hero-archive-box" message="No memories recorded" />
                <% else %>
                  <ul class="space-y-2">
                    <li :for={memory <- @recent_memories}>
                      <.memory_row memory={memory} />
                    </li>
                  </ul>
                <% end %>
              </div>
            </div>
          </div>
          
    <!-- Activity Timeline -->
          <div class="card bg-base-200 border-2 border-info/50 hover:border-info transition-colors">
            <div class="card-body p-0">
              <div class="flex items-center justify-between px-4 py-3 border-b-2 border-info/30 bg-base-300">
                <h2 class="card-title text-sm font-terminal uppercase gap-2">
                  <.icon name="hero-clock" class="size-4 text-info" /> Activity Log
                </h2>
              </div>
              <div class="p-4 max-h-80 overflow-y-auto">
                <%= if @recent_actions == [] do %>
                  <.empty_state icon="hero-clock" message="No recent activity" />
                <% else %>
                  <ul class="timeline timeline-vertical timeline-compact">
                    <li :for={action <- @recent_actions}>
                      <.timeline_item action={action} />
                    </li>
                  </ul>
                <% end %>
              </div>
            </div>
          </div>
        </div>
      </div>
    </Layouts.app>
    """
  end

  # ============================================================================
  # Component Functions
  # ============================================================================

  attr(:icon, :string, required: true)
  attr(:message, :string, required: true)

  defp empty_state(assigns) do
    ~H"""
    <div class="flex flex-col items-center justify-center py-8 text-base-content/40">
      <.icon name={@icon} class="size-10 mb-2" />
      <p class="font-terminal text-xs uppercase">{@message}</p>
    </div>
    """
  end

  attr(:belief, :map, required: true)

  defp belief_row(assigns) do
    ~H"""
    <a
      href={~p"/beliefs/#{@belief.id}"}
      class="block p-3 bg-base-300 border border-primary/20 hover:border-primary hover-lift transition-all"
    >
      <div class="flex items-start justify-between gap-2">
        <p class="text-sm font-terminal line-clamp-2">{@belief.statement}</p>
        <div class="tooltip" data-tip="Confidence">
          <span class={["badge font-terminal font-bold", confidence_badge_class(@belief.confidence)]}>
            {Float.round(@belief.confidence * 100, 0)}%
          </span>
        </div>
      </div>
      <div class="flex items-center gap-2 mt-2">
        <span class={[
          "badge badge-xs font-terminal uppercase",
          source_badge_class(@belief.source_type)
        ]}>
          {@belief.source_type}
        </span>
        <span class="text-[10px] font-terminal text-base-content/50">E:{@belief.entrenchment}</span>
      </div>
    </a>
    """
  end

  attr(:question, :map, required: true)

  defp question_row(assigns) do
    ~H"""
    <a
      href={~p"/questions/#{@question.id}"}
      class="block p-3 bg-base-300 border border-secondary/20 hover:border-secondary hover-lift transition-all"
    >
      <p class="text-sm font-terminal line-clamp-2">{@question.question}</p>
      <div class="flex items-center gap-2 mt-2">
        <span class="badge badge-warning badge-xs font-terminal">P:{@question.priority}</span>
        <span class="text-[10px] font-terminal text-base-content/50">x{@question.times_asked}</span>
      </div>
    </a>
    """
  end

  attr(:memory, :map, required: true)

  defp memory_row(assigns) do
    ~H"""
    <a
      href={~p"/memories/#{@memory.id}"}
      class="block p-3 bg-base-300 border border-accent/20 hover:border-accent hover-lift transition-all"
    >
      <p class="text-sm font-terminal line-clamp-2">{truncate(@memory.content, 100)}</p>
      <div class="flex items-center gap-2 mt-2">
        <span class={[
          "badge badge-xs font-terminal uppercase",
          memory_badge_class(@memory.memory_type)
        ]}>
          {@memory.memory_type}
        </span>
        <.importance_dots importance={@memory.importance} />
      </div>
    </a>
    """
  end

  attr(:action, :map, required: true)

  defp timeline_item(assigns) do
    ~H"""
    <div class="timeline-start timeline-box bg-base-300 border border-info/20 p-2">
      <div class="flex items-center gap-2">
        <span class="badge badge-info badge-xs font-terminal uppercase">{@action.action_type}</span>
        <span class={["badge badge-xs font-terminal uppercase", outcome_badge_class(@action.outcome)]}>
          {@action.outcome || "pending"}
        </span>
      </div>
      <%= if @action.description do %>
        <p class="text-xs font-terminal text-base-content/60 mt-1 line-clamp-1">
          {truncate(@action.description, 60)}
        </p>
      <% end %>
    </div>
    <div class="timeline-middle">
      <span class="status status-info"></span>
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

  # Style helpers
  defp confidence_badge_class(conf) when conf >= 0.8, do: "badge-success"
  defp confidence_badge_class(conf) when conf >= 0.5, do: "badge-warning"
  defp confidence_badge_class(_), do: "badge-error"

  defp source_badge_class("observation"), do: "badge-info"
  defp source_badge_class("inference"), do: "badge-secondary"
  defp source_badge_class("training"), do: "badge-warning"
  defp source_badge_class("testimony"), do: "badge-accent"
  defp source_badge_class(_), do: "badge-ghost"

  defp memory_badge_class("observation"), do: "badge-info"
  defp memory_badge_class("reflection"), do: "badge-secondary"
  defp memory_badge_class("conversation"), do: "badge-accent"
  defp memory_badge_class("plan"), do: "badge-primary"
  defp memory_badge_class(_), do: "badge-ghost"

  defp outcome_badge_class("success"), do: "badge-success"
  defp outcome_badge_class("failure"), do: "badge-error"
  defp outcome_badge_class(_), do: "badge-ghost"

  defp truncate(text, max_length) when is_binary(text) do
    if String.length(text) > max_length do
      String.slice(text, 0, max_length) <> "..."
    else
      text
    end
  end

  defp truncate(_, _), do: ""
end
