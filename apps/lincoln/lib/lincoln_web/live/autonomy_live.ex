defmodule LincolnWeb.AutonomyLive do
  @moduledoc """
  Dashboard for Lincoln's autonomous learning sessions.

  Features:
  - Start/Stop controls
  - Real-time activity feed
  - Session statistics
  - Topic queue visualization
  - Code changes tracking
  - Budget monitoring

  "I want to live. I want to experience. I want to understand."
  - Lincoln Six Echo
  """
  use LincolnWeb, :live_view

  alias Lincoln.{Agents, Autonomy}
  alias Lincoln.Autonomy.{LearningLog, LearningSession, TokenBudget}
  alias Lincoln.Workers.AutonomousLearningWorker

  @impl true
  def mount(_params, _session, socket) do
    {:ok, agent} = Agents.get_or_create_default_agent()

    # Get current session if any
    active_session = Autonomy.get_active_session(agent)
    sessions = Autonomy.list_sessions(agent, limit: 10)

    socket =
      socket
      |> assign(:agent, agent)
      |> assign(:page_title, "Autonomy - Night Shift")
      |> assign(:active_session, active_session)
      |> assign(:sessions, sessions)
      |> assign(:show_start_modal, false)
      |> assign(:seed_topics_input, default_seed_topics())
      |> load_session_data()

    # Subscribe to updates
    if connected?(socket) do
      Phoenix.PubSub.subscribe(Lincoln.PubSub, "agent:#{agent.id}:autonomy")
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
  def handle_event("show_start_modal", _params, socket) do
    {:noreply, assign(socket, :show_start_modal, true)}
  end

  def handle_event("hide_start_modal", _params, socket) do
    {:noreply, assign(socket, :show_start_modal, false)}
  end

  def handle_event("update_seed_topics", %{"topics" => topics}, socket) do
    {:noreply, assign(socket, :seed_topics_input, topics)}
  end

  def handle_event("start_session", _params, socket) do
    agent = socket.assigns.agent
    topics_input = socket.assigns.seed_topics_input

    # Parse topics (one per line)
    seed_topics =
      topics_input
      |> String.split("\n")
      |> Enum.map(&String.trim/1)
      |> Enum.reject(&(&1 == ""))

    if seed_topics != [] do
      {:ok, session} = AutonomousLearningWorker.start_session(agent, seed_topics)

      socket =
        socket
        |> assign(:active_session, session)
        |> assign(:show_start_modal, false)
        |> load_session_data()
        |> put_flash(:info, "Autonomous learning started! Lincoln is now exploring...")

      {:noreply, socket}
    else
      {:noreply, put_flash(socket, :error, "Please enter at least one seed topic")}
    end
  end

  def handle_event("stop_session", _params, socket) do
    session = socket.assigns.active_session

    if session do
      {:ok, stopped_session} = Autonomy.stop_session(session)

      Autonomy.log_activity(
        socket.assigns.agent,
        stopped_session,
        "session_stop",
        "Session stopped by user"
      )

      socket =
        socket
        |> assign(:active_session, nil)
        |> put_flash(:info, "Learning session stopped")

      {:noreply, socket}
    else
      {:noreply, socket}
    end
  end

  def handle_event("pause_session", _params, socket) do
    session = socket.assigns.active_session

    if session && LearningSession.running?(session) do
      {:ok, paused_session} = Autonomy.pause_session(session)
      {:noreply, assign(socket, :active_session, paused_session)}
    else
      {:noreply, socket}
    end
  end

  def handle_event("resume_session", _params, socket) do
    session = socket.assigns.active_session

    if session && session.status == "paused" do
      {:ok, resumed_session} = Autonomy.resume_session(session)
      AutonomousLearningWorker.start(resumed_session)
      {:noreply, assign(socket, :active_session, resumed_session)}
    else
      {:noreply, socket}
    end
  end

  # ============================================================================
  # PubSub Handlers
  # ============================================================================

  @impl true
  def handle_info({:log_entry, log}, socket) do
    socket =
      socket
      |> stream_insert(:logs, log, at: 0)
      |> maybe_update_session()

    {:noreply, socket}
  end

  def handle_info({:session_started, session}, socket) do
    {:noreply, assign(socket, :active_session, session)}
  end

  def handle_info({:session_stopped, _session}, socket) do
    sessions = Autonomy.list_sessions(socket.assigns.agent, limit: 10)

    socket =
      socket
      |> assign(:active_session, nil)
      |> assign(:sessions, sessions)
      |> put_flash(:info, "Learning session completed")

    {:noreply, socket}
  end

  def handle_info({:topic_created, _topic}, socket) do
    {:noreply, load_session_data(socket)}
  end

  def handle_info({:topic_completed, _topic}, socket) do
    {:noreply, load_session_data(socket)}
  end

  def handle_info({:code_change_applied, _change}, socket) do
    {:noreply, load_session_data(socket)}
  end

  def handle_info(_msg, socket) do
    {:noreply, socket}
  end

  # ============================================================================
  # Private Helpers
  # ============================================================================

  defp load_session_data(socket) do
    case socket.assigns.active_session do
      nil ->
        socket
        |> assign(:stats, nil)
        |> assign(:pending_topics, [])
        |> assign(:code_changes, [])
        |> stream(:logs, [], reset: true)

      session ->
        # Reload session to get latest counts
        session = Autonomy.get_session!(session.id)
        stats = Autonomy.get_session_stats(session)
        pending_topics = Autonomy.list_pending_topics(session, limit: 15)
        code_changes = Autonomy.list_code_changes(session, limit: 10)
        logs = Autonomy.list_logs(session, limit: 50)

        socket
        |> assign(:active_session, session)
        |> assign(:stats, stats)
        |> assign(:pending_topics, pending_topics)
        |> assign(:code_changes, code_changes)
        |> stream(:logs, logs, reset: true)
    end
  end

  defp maybe_update_session(socket) do
    case socket.assigns.active_session do
      nil -> socket
      session -> assign(socket, :active_session, Autonomy.get_session!(session.id))
    end
  end

  defp default_seed_topics do
    """
    Computer Architecture
    Data Structures and Algorithms
    Operating Systems
    Computer Networks
    Programming Language Theory
    History of Computing
    """
  end

  # ============================================================================
  # Render
  # ============================================================================

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash}>
      <div class="space-y-6">
        <!-- Header with Controls -->
        <div class="bg-base-200 border border-base-300 rounded-lg p-6">
          <div class="flex flex-col lg:flex-row items-start lg:items-center justify-between gap-4">
            <div class="flex items-center gap-4">
              <div class="avatar placeholder">
                <div class={[
                  "w-14 rounded-lg transition-all",
                  if(@active_session && LearningSession.running?(@active_session),
                    do: "bg-accent text-accent-content animate-pulse",
                    else: "bg-base-300 text-base-content/50"
                  )
                ]}>
                  <span class="text-2xl font-bold">L</span>
                </div>
              </div>
              <div>
                <h1 class="text-2xl font-semibold">Night Shift</h1>
                <p class="text-base-content/60 text-sm">
                  <%= if @active_session && LearningSession.running?(@active_session) do %>
                    <span class="text-accent">Autonomous learning active</span>
                  <% else %>
                    Autonomous learning system
                  <% end %>
                </p>
              </div>
            </div>

            <div class="flex gap-2">
              <%= if @active_session && LearningSession.running?(@active_session) do %>
                <button phx-click="stop_session" class="btn btn-error gap-2">
                  <.icon name="hero-stop" class="w-5 h-5" /> Stop Learning
                </button>
              <% else %>
                <button
                  phx-click="show_start_modal"
                  class="btn btn-accent gap-2"
                >
                  <.icon name="hero-play" class="w-5 h-5" /> Start Night Shift
                </button>
              <% end %>
            </div>
          </div>
        </div>
        
    <!-- Stats Grid -->
        <%= if @stats do %>
          <div class="grid grid-cols-2 sm:grid-cols-5 gap-4">
            <div class="bg-base-200 border border-base-300 rounded-lg p-4">
              <div class="flex items-center justify-between">
                <div class="text-xs uppercase text-base-content/60">Duration</div>
                <.icon name="hero-clock" class="w-5 h-5 text-primary" />
              </div>
              <div class="text-2xl font-semibold text-primary mt-2">
                {format_duration(@stats.duration_minutes)}
              </div>
            </div>

            <div class="bg-base-200 border border-base-300 rounded-lg p-4">
              <div class="flex items-center justify-between">
                <div class="text-xs uppercase text-base-content/60">Topics</div>
                <.icon name="hero-magnifying-glass" class="w-5 h-5 text-secondary" />
              </div>
              <div class="text-2xl font-semibold text-secondary mt-2">
                {@stats.topics_explored}
              </div>
              <div class="text-xs text-base-content/50 mt-1">{@stats.topics_pending} pending</div>
            </div>

            <div class="bg-base-200 border border-base-300 rounded-lg p-4">
              <div class="flex items-center justify-between">
                <div class="text-xs uppercase text-base-content/60">Beliefs</div>
                <.icon name="hero-light-bulb" class="w-5 h-5 text-accent" />
              </div>
              <div class="text-2xl font-semibold text-accent mt-2">
                {@stats.beliefs_formed}
              </div>
            </div>

            <div class="bg-base-200 border border-base-300 rounded-lg p-4">
              <div class="flex items-center justify-between">
                <div class="text-xs uppercase text-base-content/60">Code Changes</div>
                <.icon name="hero-code-bracket" class="w-5 h-5 text-info" />
              </div>
              <div class="text-2xl font-semibold text-info mt-2">
                {@stats.code_changes}
              </div>
            </div>

            <div class="bg-base-200 border border-base-300 rounded-lg p-4">
              <div class="flex items-center justify-between">
                <div class="text-xs uppercase text-base-content/60">Tokens</div>
                <.icon name="hero-currency-dollar" class="w-5 h-5 text-warning" />
              </div>
              <div class="text-2xl font-semibold text-warning mt-2">
                {format_tokens(@stats.tokens_used)}
              </div>
              <div class="text-xs text-base-content/50 mt-1">
                {TokenBudget.format_cost(@stats.tokens_used)}
              </div>
            </div>
          </div>
        <% end %>
        
    <!-- Main Content Grid -->
        <div class="grid lg:grid-cols-3 gap-6">
          <!-- Activity Log (2 columns) -->
          <div class="lg:col-span-2 bg-base-200 border border-base-300 rounded-lg">
            <div class="flex items-center justify-between px-4 py-3 border-b border-base-300">
              <h2 class="text-sm font-semibold flex items-center gap-2">
                <.icon name="hero-bolt" class="w-4 h-4 text-info" /> Live Activity
              </h2>
              <%= if @active_session && LearningSession.running?(@active_session) do %>
                <span class="badge badge-info badge-sm gap-1">
                  <span class="w-2 h-2 rounded-full bg-success animate-pulse"></span> Live
                </span>
              <% end %>
            </div>
            <div class="p-4 h-96 overflow-y-auto" id="activity-log" phx-hook="ScrollToBottom">
              <div id="logs-stream" phx-update="stream" class="space-y-2">
                <div class="hidden only:flex flex-col items-center justify-center h-full text-center">
                  <.icon name="hero-bolt" class="w-12 h-12 text-base-content/20 mb-2" />
                  <p class="text-sm text-base-content/40">
                    No activity yet. Start a learning session to see Lincoln in action.
                  </p>
                </div>

                <.log_entry :for={{dom_id, log} <- @streams.logs} id={dom_id} log={log} />
              </div>
            </div>
          </div>
          
    <!-- Side Panel -->
          <div class="space-y-6">
            <!-- Topic Queue -->
            <div class="bg-base-200 border border-base-300 rounded-lg">
              <div class="px-4 py-3 border-b border-base-300">
                <h2 class="text-sm font-semibold flex items-center gap-2">
                  <.icon name="hero-queue-list" class="w-4 h-4 text-secondary" /> Topic Queue
                </h2>
              </div>
              <div class="p-4 max-h-64 overflow-y-auto">
                <%= if @pending_topics == [] do %>
                  <p class="text-center text-base-content/40 text-sm py-4">
                    No pending topics
                  </p>
                <% else %>
                  <ul class="space-y-2">
                    <li :for={topic <- @pending_topics}>
                      <div class="flex items-center gap-2 p-2 bg-base-300 rounded-lg">
                        <span class="badge badge-secondary badge-xs">
                          P{topic.priority}
                        </span>
                        <span class="text-sm flex-1 truncate">
                          {topic.topic}
                        </span>
                        <span class="badge badge-ghost badge-xs">
                          D{topic.depth}
                        </span>
                      </div>
                    </li>
                  </ul>
                <% end %>
              </div>
            </div>
            
    <!-- Code Changes -->
            <div class="bg-base-200 border border-base-300 rounded-lg">
              <div class="px-4 py-3 border-b border-base-300">
                <h2 class="text-sm font-semibold flex items-center gap-2">
                  <.icon name="hero-code-bracket" class="w-4 h-4 text-accent" /> Self-Modifications
                </h2>
              </div>
              <div class="p-4 max-h-48 overflow-y-auto">
                <%= if @code_changes == [] do %>
                  <p class="text-center text-base-content/40 text-sm py-4">
                    No code changes yet
                  </p>
                <% else %>
                  <ul class="space-y-2">
                    <li :for={change <- @code_changes}>
                      <div class="p-2 bg-base-300 rounded-lg">
                        <div class="flex items-center gap-2">
                          <span class={["badge badge-xs", change_type_badge(change.change_type)]}>
                            {change.change_type}
                          </span>
                          <span class="text-xs text-base-content/60 truncate">
                            {change.file_path}
                          </span>
                        </div>
                        <p class="text-sm mt-1 line-clamp-2">
                          {change.description}
                        </p>
                      </div>
                    </li>
                  </ul>
                <% end %>
              </div>
            </div>
          </div>
        </div>
        
    <!-- Past Sessions -->
        <%= if @sessions != [] do %>
          <div class="bg-base-200 border border-base-300 rounded-lg">
            <div class="px-4 py-3 border-b border-base-300">
              <h2 class="text-sm font-semibold flex items-center gap-2">
                <.icon name="hero-archive-box" class="w-4 h-4" /> Past Sessions
              </h2>
            </div>
            <div class="p-4">
              <div class="overflow-x-auto">
                <table class="table table-zebra text-sm">
                  <thead>
                    <tr>
                      <th>Started</th>
                      <th>Duration</th>
                      <th>Topics</th>
                      <th>Beliefs</th>
                      <th>Status</th>
                    </tr>
                  </thead>
                  <tbody>
                    <tr :for={session <- @sessions}>
                      <td>{format_datetime(session.started_at)}</td>
                      <td>{format_session_duration(session)}</td>
                      <td>{session.topics_explored}</td>
                      <td>{session.beliefs_formed}</td>
                      <td>
                        <span class={["badge badge-sm", status_badge(session.status)]}>
                          {session.status}
                        </span>
                      </td>
                    </tr>
                  </tbody>
                </table>
              </div>
            </div>
          </div>
        <% end %>
      </div>
      
    <!-- Start Session Modal -->
      <dialog id="start-modal" class={["modal", @show_start_modal && "modal-open"]}>
        <div class="modal-box bg-base-200 border border-base-300">
          <h3 class="text-lg font-semibold">Start Night Shift</h3>
          <p class="py-4 text-sm text-base-content/70">
            Lincoln will autonomously explore these seed topics, learning and forming beliefs.
            He may discover related topics and potentially improve his own code.
          </p>

          <form phx-submit="start_session">
            <div class="form-control">
              <label class="label">
                <span class="label-text text-xs uppercase">
                  Seed Topics (one per line)
                </span>
              </label>
              <textarea
                name="topics"
                class="textarea textarea-bordered h-48"
                phx-change="update_seed_topics"
              >{@seed_topics_input}</textarea>
            </div>

            <div class="modal-action">
              <button type="button" phx-click="hide_start_modal" class="btn btn-ghost">
                Cancel
              </button>
              <button type="submit" class="btn btn-accent gap-2">
                <.icon name="hero-play" class="w-4 h-4" /> Begin Learning
              </button>
            </div>
          </form>
        </div>
        <form method="dialog" class="modal-backdrop">
          <button phx-click="hide_start_modal">close</button>
        </form>
      </dialog>
    </Layouts.app>
    """
  end

  # ============================================================================
  # Components
  # ============================================================================

  attr(:id, :string, required: true)
  attr(:log, :map, required: true)

  defp log_entry(assigns) do
    ~H"""
    <div
      id={@id}
      class={[
        "flex items-start gap-3 p-2 border-l-2 bg-base-300/50 rounded-r-lg",
        log_border_color(@log.activity_type)
      ]}
    >
      <div class={["mt-0.5", "text-#{LearningLog.activity_color(@log.activity_type)}"]}>
        <.icon name={LearningLog.activity_icon(@log.activity_type)} class="w-4 h-4" />
      </div>
      <div class="flex-1 min-w-0">
        <div class="flex items-center gap-2">
          <span class={[
            "badge badge-xs",
            "badge-#{LearningLog.activity_color(@log.activity_type)}"
          ]}>
            {@log.activity_type}
          </span>
          <span class="text-xs text-base-content/40">
            {format_time(@log.inserted_at)}
          </span>
          <%= if @log.tokens_used > 0 do %>
            <span class="text-xs text-warning/60">
              {format_tokens(@log.tokens_used)} tokens
            </span>
          <% end %>
        </div>
        <p class="text-sm mt-1">{@log.description}</p>
      </div>
    </div>
    """
  end

  # ============================================================================
  # Helpers
  # ============================================================================

  defp log_border_color(activity_type) do
    case activity_type do
      "error" -> "border-error"
      "believe" -> "border-primary"
      "code_change" -> "border-accent"
      "reflect" -> "border-info"
      "session_start" -> "border-success"
      "session_stop" -> "border-warning"
      _ -> "border-base-content/20"
    end
  end

  defp change_type_badge("create"), do: "badge-success"
  defp change_type_badge("modify"), do: "badge-info"
  defp change_type_badge("refactor"), do: "badge-warning"
  defp change_type_badge("improve"), do: "badge-accent"
  defp change_type_badge(_), do: "badge-ghost"

  defp status_badge("running"), do: "badge-success"
  defp status_badge("paused"), do: "badge-warning"
  defp status_badge("stopped"), do: "badge-error"
  defp status_badge("completed"), do: "badge-info"
  defp status_badge(_), do: "badge-ghost"

  defp format_duration(minutes) when minutes < 60 do
    "#{minutes}m"
  end

  defp format_duration(minutes) do
    hours = div(minutes, 60)
    mins = rem(minutes, 60)
    "#{hours}h #{mins}m"
  end

  defp format_tokens(tokens) when tokens < 1000, do: "#{tokens}"
  defp format_tokens(tokens), do: "#{Float.round(tokens / 1000, 1)}k"

  defp format_time(datetime) do
    Calendar.strftime(datetime, "%H:%M:%S")
  end

  defp format_datetime(nil), do: "-"

  defp format_datetime(datetime) do
    Calendar.strftime(datetime, "%b %d %H:%M")
  end

  defp format_session_duration(%{started_at: nil}), do: "-"

  defp format_session_duration(%{started_at: started_at, stopped_at: nil}) do
    minutes = DateTime.diff(DateTime.utc_now(), started_at, :minute)
    format_duration(minutes)
  end

  defp format_session_duration(%{started_at: started_at, stopped_at: stopped_at}) do
    minutes = DateTime.diff(stopped_at, started_at, :minute)
    format_duration(minutes)
  end
end
