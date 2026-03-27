defmodule LincolnWeb.ChatLive do
  @moduledoc """
  Main chat interface with cognitive transparency.

  Features:
  - Conversation history sidebar
  - Real-time cognitive process display
  - Worker activity sidebar (live events from autonomy system)
  - Memory access and recall
  - Research instruction capability
  - Code modification requests
  - Mobile responsive
  """
  use LincolnWeb, :live_view

  alias Lincoln.{Agents, Autonomy, Conversation}
  alias Lincoln.Cognition.ConversationHandler

  # Maximum worker events to keep in sidebar
  @max_worker_events 50

  # Event filter categories
  @event_filters %{
    "all" => nil,
    "struggles" => ~w(thought_loop_gave_up thought_loop_slow low_confidence_response),
    "learning" => ~w(belief_formed belief_revised knowledge_gap_detected),
    "corrections" => ~w(user_correction belief_contradiction),
    "improvements" => ~w(improvement_opportunity code_change_applied improvement_observed),
    "errors" => ~w(error_occurred research_failed slow_operation)
  }

  @impl true
  def mount(_params, _session, socket) do
    {:ok, agent} = Agents.get_or_create_default_agent()
    conversations = Conversation.list_conversations(agent.id, limit: 20)
    active_session = Autonomy.get_active_session_summary(agent)

    socket =
      socket
      |> assign(:agent, agent)
      |> assign(:page_title, "Chat")
      |> assign(:conversations, conversations)
      |> assign(:conversation, nil)
      |> assign(:input, "")
      |> assign(:show_sidebar, false)
      |> assign(:show_worker_sidebar, false)
      |> assign(:processing, false)
      |> assign(:thinking_step, nil)
      |> assign(:expanded_thinking, nil)
      |> assign(:worker_events, [])
      |> assign(:cognitive_events, [])
      |> assign(:event_filter, "all")
      |> assign(:active_session, active_session)
      |> stream(:messages, [])

    if connected?(socket) do
      Phoenix.PubSub.subscribe(Lincoln.PubSub, "agent:#{agent.id}:chat")
      Phoenix.PubSub.subscribe(Lincoln.PubSub, "agent:#{agent.id}:autonomy")
      Phoenix.PubSub.subscribe(Lincoln.PubSub, "agent:#{agent.id}:events")
    end

    {:ok, socket}
  end

  @impl true
  def handle_params(%{"id" => id}, _uri, socket) do
    conversation = Conversation.get_conversation_with_messages(id)

    socket =
      socket
      |> assign(:conversation, conversation)
      |> assign(:page_title, conversation.title || "Chat")
      |> stream(:messages, conversation.messages, reset: true)

    {:noreply, socket}
  end

  def handle_params(_params, _uri, socket) do
    {:noreply, socket}
  end

  # ============================================================================
  # Event Handlers
  # ============================================================================

  @impl true
  def handle_event("send_message", %{"message" => ""}, socket), do: {:noreply, socket}

  def handle_event("send_message", %{"message" => content}, socket) do
    # Prevent double submission while processing
    if socket.assigns.processing do
      {:noreply, socket}
    else
      # Ensure we have a conversation
      socket = ensure_conversation(socket)

      # Add user message immediately
      {:ok, user_msg} =
        Conversation.add_user_message(socket.assigns.conversation.id, content)

      socket =
        socket
        |> stream_insert(:messages, user_msg)
        |> assign(:input, "")
        |> assign(:processing, true)
        |> assign(:thinking_step, "Perceiving...")

      # Process through cognitive pipeline (async)
      send(self(), {:process_message, content})

      {:noreply, socket}
    end
  end

  def handle_event("toggle_sidebar", _params, socket) do
    {:noreply, assign(socket, :show_sidebar, !socket.assigns.show_sidebar)}
  end

  def handle_event("toggle_worker_sidebar", _params, socket) do
    {:noreply, assign(socket, :show_worker_sidebar, !socket.assigns.show_worker_sidebar)}
  end

  def handle_event("new_conversation", _params, socket) do
    {:noreply,
     socket
     |> assign(:conversation, nil)
     |> assign(:page_title, "Chat")
     |> stream(:messages, [], reset: true)}
  end

  def handle_event("load_conversation", %{"id" => id}, socket) do
    conversation = Conversation.get_conversation_with_messages(id)

    {:noreply,
     socket
     |> assign(:conversation, conversation)
     |> assign(:page_title, conversation.title || "Chat")
     |> assign(:show_sidebar, false)
     |> stream(:messages, conversation.messages, reset: true)}
  end

  def handle_event("expand_thinking", %{"id" => id}, socket) do
    expanded = if socket.assigns.expanded_thinking == id, do: nil, else: id
    {:noreply, assign(socket, :expanded_thinking, expanded)}
  end

  def handle_event("input_change", %{"message" => value}, socket) do
    {:noreply, assign(socket, :input, value)}
  end

  # Handle initial phx-change event before any value is set
  def handle_event("input_change", _params, socket) do
    {:noreply, socket}
  end

  def handle_event("filter_events", %{"filter" => filter}, socket) do
    {:noreply, assign(socket, :event_filter, filter)}
  end

  # ============================================================================
  # Async Message Handling
  # ============================================================================

  @impl true
  def handle_info({:process_message, content}, socket) do
    agent = socket.assigns.agent
    conversation = socket.assigns.conversation

    result =
      ConversationHandler.process_message(
        agent.id,
        conversation.id,
        content
      )

    case result do
      {:ok, cognitive_result} ->
        # Add Lincoln's response with cognitive metadata
        {:ok, assistant_msg} =
          Conversation.add_assistant_message(
            conversation.id,
            cognitive_result.response,
            %{
              memories_retrieved: cognitive_result.cognitive_metadata.memories_retrieved,
              beliefs_consulted: cognitive_result.cognitive_metadata.beliefs_consulted,
              beliefs_formed: cognitive_result.cognitive_metadata.beliefs_formed,
              beliefs_revised: cognitive_result.cognitive_metadata.beliefs_revised,
              questions_generated: cognitive_result.cognitive_metadata.questions_generated,
              contradiction_detected: cognitive_result.cognitive_metadata.contradiction_detected,
              thinking_summary: cognitive_result.cognitive_metadata.thinking_summary
            }
          )

        # Reload conversations list to show updated title
        conversations = Conversation.list_conversations(agent.id, limit: 20)

        socket =
          socket
          |> stream_insert(:messages, assistant_msg)
          |> assign(:processing, false)
          |> assign(:thinking_step, nil)
          |> assign(:conversations, conversations)

        {:noreply, socket}

      {:error, reason} ->
        socket =
          socket
          |> put_flash(:error, "Failed to process message: #{inspect(reason)}")
          |> assign(:processing, false)
          |> assign(:thinking_step, nil)

        {:noreply, socket}
    end
  end

  def handle_info({:thinking, step}, socket) do
    {:noreply, assign(socket, :thinking_step, step)}
  end

  # ============================================================================
  # Autonomy Event Handlers (Worker Lincoln Activity)
  # ============================================================================

  def handle_info({:autonomy, :session_started, session}, socket) do
    # Use seed_topics as the detail since trigger field doesn't exist
    detail =
      case session.seed_topics do
        [first | _] -> "Starting with: #{first}"
        _ -> nil
      end

    event = %{
      type: :session,
      icon: "hero-play",
      message: "Started learning session",
      detail: detail,
      timestamp: DateTime.utc_now() |> DateTime.truncate(:second)
    }

    {:noreply,
     socket
     |> prepend_worker_event(event)
     |> assign(:active_session, Autonomy.get_active_session_summary(socket.assigns.agent))}
  end

  def handle_info({:autonomy, :session_stopped, _session}, socket) do
    event = %{
      type: :session,
      icon: "hero-stop",
      message: "Learning session completed",
      detail: nil,
      timestamp: DateTime.utc_now() |> DateTime.truncate(:second)
    }

    {:noreply,
     socket
     |> prepend_worker_event(event)
     |> assign(:active_session, nil)}
  end

  def handle_info({:autonomy, :topic_completed, topic}, socket) do
    event = %{
      type: :topic,
      icon: "hero-check-circle",
      message: "Explored: #{truncate_text(topic.topic, 30)}",
      detail: "#{topic.facts_extracted || 0} facts found",
      timestamp: DateTime.utc_now() |> DateTime.truncate(:second)
    }

    {:noreply, prepend_worker_event(socket, event)}
  end

  def handle_info({:autonomy, :code_change_committed, change}, socket) do
    event = %{
      type: :evolution,
      icon: "hero-code-bracket",
      message: "Modified: #{Path.basename(change.file_path)}",
      detail: truncate_text(change.description, 50),
      timestamp: DateTime.utc_now() |> DateTime.truncate(:second)
    }

    {:noreply, prepend_worker_event(socket, event)}
  end

  def handle_info({:autonomy, :log_entry, log}, socket) do
    handle_log_entry(log, socket)
  end

  # Direct log_entry format (from autonomy.ex broadcast)
  def handle_info({:log_entry, log}, socket) do
    handle_log_entry(log, socket)
  end

  # ============================================================================
  # Cognitive Event Handlers (from Events system)
  # ============================================================================

  def handle_info({:event, event}, socket) do
    cognitive_event = %{
      id: event.id,
      type: event.type,
      severity: event.severity,
      icon: cognitive_event_icon(event.type),
      message: cognitive_event_message(event.type, event.context),
      detail: cognitive_event_detail(event),
      timestamp: event.inserted_at
    }

    {:noreply, prepend_cognitive_event(socket, cognitive_event)}
  end

  # Catch-all for other autonomy events (must be after all specific handlers)
  def handle_info({:autonomy, _event, _data}, socket) do
    {:noreply, socket}
  end

  # Catch-all for other direct PubSub events from autonomy channel
  # (e.g., :topic_created, :topic_started, etc.)
  def handle_info({event_type, _data}, socket)
      when event_type in [
             :topic_created,
             :topic_started,
             :topic_completed,
             :session_created,
             :belief_formed,
             :memory_created
           ] do
    {:noreply, socket}
  end

  # ============================================================================
  # Private Helpers for Event Handlers
  # ============================================================================

  defp handle_log_entry(log, socket) do
    # Only show significant log entries
    if log.activity_type in [
         "believe",
         "memorize",
         "reflect",
         "evolve",
         "code_change",
         "topic_complete"
       ] do
      event = %{
        type: String.to_atom(log.activity_type),
        icon: activity_icon(log.activity_type),
        message: truncate_text(log.description, 40),
        detail: nil,
        timestamp: DateTime.utc_now() |> DateTime.truncate(:second)
      }

      {:noreply, prepend_worker_event(socket, event)}
    else
      {:noreply, socket}
    end
  end

  defp prepend_cognitive_event(socket, event) do
    events = [event | socket.assigns.cognitive_events] |> Enum.take(@max_worker_events)
    assign(socket, :cognitive_events, events)
  end

  defp cognitive_event_icon(type) do
    case type do
      "thought_loop_gave_up" -> "hero-x-circle"
      "thought_loop_slow" -> "hero-clock"
      "low_confidence_response" -> "hero-question-mark-circle"
      "user_correction" -> "hero-pencil-square"
      "knowledge_gap_detected" -> "hero-magnifying-glass"
      "belief_contradiction" -> "hero-exclamation-triangle"
      "research_failed" -> "hero-x-mark"
      "belief_formed" -> "hero-light-bulb"
      "belief_revised" -> "hero-arrow-path"
      "error_occurred" -> "hero-bug-ant"
      "slow_operation" -> "hero-clock"
      "improvement_opportunity" -> "hero-sparkles"
      "code_change_applied" -> "hero-code-bracket"
      "improvement_observed" -> "hero-eye"
      _ -> "hero-bolt"
    end
  end

  defp cognitive_event_message(type, context) do
    case type do
      "thought_loop_gave_up" ->
        "Gave up after #{context["iterations"] || "?"} iterations"

      "thought_loop_slow" ->
        "Slow thinking: #{context["duration_ms"] || "?"}ms"

      "low_confidence_response" ->
        "Low confidence: #{Float.round((context["confidence"] || 0) * 100, 0)}%"

      "user_correction" ->
        "User corrected response"

      "knowledge_gap_detected" ->
        "Knowledge gap: #{truncate_text(context["topic"] || "unknown", 30)}"

      "belief_contradiction" ->
        "Belief contradiction detected"

      "research_failed" ->
        "Research failed"

      "belief_formed" ->
        "New belief formed"

      "belief_revised" ->
        "Belief revised"

      "error_occurred" ->
        "Error: #{truncate_text(context["error"] || "unknown", 30)}"

      "slow_operation" ->
        "Slow operation: #{context["operation"] || "unknown"}"

      "improvement_opportunity" ->
        "Improvement opportunity identified"

      "code_change_applied" ->
        "Code modified: #{Path.basename(context["file_path"] || "unknown")}"

      "improvement_observed" ->
        "Improvement outcome observed"

      _ ->
        type
    end
  end

  defp cognitive_event_detail(event) do
    case event.type do
      "user_correction" ->
        if event.context["correction_type"],
          do: "Type: #{event.context["correction_type"]}",
          else: nil

      "belief_formed" ->
        truncate_text(event.context["statement"], 50)

      "belief_revised" ->
        "Confidence: #{event.context["old_confidence"]} → #{event.context["new_confidence"]}"

      "code_change_applied" ->
        truncate_text(event.context["description"], 50)

      _ ->
        nil
    end
  end

  defp prepend_worker_event(socket, event) do
    events = [event | socket.assigns.worker_events] |> Enum.take(@max_worker_events)
    assign(socket, :worker_events, events)
  end

  defp activity_icon(type) do
    case type do
      "believe" -> "hero-light-bulb"
      "memorize" -> "hero-archive-box"
      "reflect" -> "hero-eye"
      "evolve" -> "hero-arrow-path"
      "code_change" -> "hero-code-bracket"
      "topic_complete" -> "hero-check-circle"
      "topic_start" -> "hero-magnifying-glass"
      "question" -> "hero-question-mark-circle"
      _ -> "hero-bolt"
    end
  end

  defp truncate_text(nil, _len), do: ""

  defp truncate_text(text, len) when is_binary(text) do
    if String.length(text) > len do
      String.slice(text, 0, len) <> "..."
    else
      text
    end
  end

  # ============================================================================
  # Private Functions
  # ============================================================================

  defp ensure_conversation(socket) do
    case socket.assigns.conversation do
      nil ->
        {:ok, conversation} = Conversation.create_conversation(socket.assigns.agent.id)
        assign(socket, :conversation, conversation)

      _conversation ->
        socket
    end
  end

  # ============================================================================
  # Render
  # ============================================================================

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash}>
      <div class="h-[calc(100vh-4rem)] flex relative">
        <!-- Mobile sidebar overlay -->
        <div
          :if={@show_sidebar || @show_worker_sidebar}
          class="fixed inset-0 bg-black/50 z-30 lg:hidden"
          phx-click={if @show_sidebar, do: "toggle_sidebar", else: "toggle_worker_sidebar"}
        >
        </div>
        
    <!-- Conversation Sidebar (left) -->
        <.conversation_sidebar
          conversations={@conversations}
          current={@conversation}
          show={@show_sidebar}
        />
        
    <!-- Main Chat Area -->
        <main class="flex-1 flex flex-col min-w-0 bg-base-100">
          <!-- Chat Header -->
          <.chat_header
            conversation={@conversation}
            show_worker_sidebar={@show_worker_sidebar}
            has_active_session={@active_session != nil}
            worker_event_count={length(@worker_events)}
          />
          
    <!-- Messages Area - KEY FIX: min-h-0 allows flex child to scroll -->
          <div
            class="flex-1 overflow-y-auto min-h-0"
            id="lincoln-messages"
            phx-hook="ScrollToBottom"
          >
            <div id="messages-stream" phx-update="stream" class="space-y-4 p-4">
              <!-- Empty state -->
              <div class="hidden only:flex flex-col items-center justify-center h-full text-center p-8">
                <div class="w-16 h-16 rounded-lg bg-primary flex items-center justify-center mb-4">
                  <span class="text-2xl font-bold text-primary-content">L</span>
                </div>
                <h2 class="font-semibold text-lg mb-2">Start a Conversation</h2>
                <p class="text-sm text-base-content/60 max-w-sm">
                  Talk to Lincoln and watch him learn. He remembers conversations, forms beliefs, and
                  can revise his understanding based on new evidence.
                </p>
                <div class="mt-4 text-xs text-base-content/40 space-y-1">
                  <p>Try: "research [topic]" to queue autonomous learning</p>
                  <p>Try: "improve yourself" to trigger self-modification</p>
                  <p>Try: "show me belief_formation.ex" to view code</p>
                </div>
              </div>
              
    <!-- Messages -->
              <.message_bubble
                :for={{dom_id, msg} <- @streams.messages}
                id={dom_id}
                message={msg}
                expanded={@expanded_thinking == msg.id}
              />
            </div>
            
    <!-- Thinking indicator -->
            <.thinking_indicator :if={@processing} step={@thinking_step} />
          </div>
          
    <!-- Input Area -->
          <.chat_input value={@input} disabled={@processing} />
        </main>
        
    <!-- Worker Activity Sidebar (right) -->
        <.worker_sidebar
          show={@show_worker_sidebar}
          worker_events={@worker_events}
          cognitive_events={@cognitive_events}
          event_filter={@event_filter}
          active_session={@active_session}
        />
      </div>
    </Layouts.app>
    """
  end

  # ============================================================================
  # Private Components
  # ============================================================================

  attr(:conversations, :list, required: true)
  attr(:current, :map, default: nil)
  attr(:show, :boolean, default: false)

  defp conversation_sidebar(assigns) do
    ~H"""
    <aside class={[
      "w-64 bg-base-200 border-r border-base-300 flex flex-col",
      "fixed inset-y-0 left-0 z-40 transition-transform duration-200",
      "lg:relative lg:translate-x-0",
      if(@show, do: "translate-x-0", else: "-translate-x-full")
    ]}>
      <div class="p-4 border-b border-base-300 flex items-center justify-between shrink-0">
        <h2 class="font-semibold text-sm">History</h2>
        <button phx-click="new_conversation" class="btn btn-primary btn-xs gap-1">
          <.icon name="hero-plus" class="w-3 h-3" /> New
        </button>
      </div>

      <div class="flex-1 overflow-y-auto min-h-0">
        <ul class="menu p-2 gap-1">
          <%= if @conversations == [] do %>
            <li class="text-xs text-base-content/40 p-4 text-center">
              No conversations yet
            </li>
          <% else %>
            <li :for={conv <- @conversations}>
              <button
                phx-click="load_conversation"
                phx-value-id={conv.id}
                class={[
                  "text-sm justify-start",
                  @current && @current.id == conv.id && "active"
                ]}
              >
                <.icon name="hero-chat-bubble-left-right" class="w-4 h-4 shrink-0" />
                <span class="truncate flex-1 text-left">{conv.title || "Untitled"}</span>
                <span class="badge badge-xs badge-ghost">{conv.message_count}</span>
              </button>
            </li>
          <% end %>
        </ul>
      </div>

      <div class="p-4 border-t border-base-300 text-xs text-base-content/40 shrink-0">
        <div class="flex items-center gap-2">
          <span class="w-2 h-2 rounded-full bg-success"></span> Learning Active
        </div>
      </div>
    </aside>
    """
  end

  attr(:conversation, :map, default: nil)
  attr(:show_worker_sidebar, :boolean, default: false)
  attr(:has_active_session, :boolean, default: false)
  attr(:worker_event_count, :integer, default: 0)

  defp chat_header(assigns) do
    ~H"""
    <header class="h-14 flex items-center justify-between px-4 border-b border-base-300 bg-base-200 shrink-0">
      <div class="flex items-center gap-3">
        <!-- Mobile sidebar toggle -->
        <button phx-click="toggle_sidebar" class="btn btn-ghost btn-sm btn-square lg:hidden">
          <.icon name="hero-bars-3" class="w-5 h-5" />
        </button>

        <div class="w-10 h-10 rounded-lg bg-primary flex items-center justify-center">
          <span class="font-bold text-primary-content">L</span>
        </div>
        <div>
          <h1 class="font-semibold">Lincoln</h1>
          <p class="text-xs text-base-content/60">
            {if @conversation, do: @conversation.title || "New conversation", else: "Start chatting"}
          </p>
        </div>
      </div>

      <div class="flex items-center gap-2">
        <!-- Worker activity toggle -->
        <button
          phx-click="toggle_worker_sidebar"
          class={[
            "btn btn-sm gap-1 relative",
            if(@show_worker_sidebar, do: "btn-secondary", else: "btn-ghost")
          ]}
          title="Worker Lincoln Activity"
        >
          <.icon name="hero-cpu-chip" class="w-4 h-4" />
          <span class="hidden sm:inline">Worker</span>
          <%= if @has_active_session do %>
            <span class="absolute -top-1 -right-1 w-3 h-3 bg-success rounded-full animate-pulse">
            </span>
          <% end %>
          <%= if @worker_event_count > 0 and not @show_worker_sidebar do %>
            <span class="badge badge-xs badge-secondary">{@worker_event_count}</span>
          <% end %>
        </button>
        
    <!-- New chat button -->
        <button phx-click="new_conversation" class="btn btn-outline btn-primary btn-sm gap-1">
          <.icon name="hero-plus" class="w-4 h-4" />
          <span class="hidden sm:inline">New</span>
        </button>
      </div>
    </header>
    """
  end

  attr(:id, :string, required: true)
  attr(:message, :map, required: true)
  attr(:expanded, :boolean, default: false)

  defp message_bubble(assigns) do
    ~H"""
    <%= if @message.role == "user" do %>
      <!-- User message -->
      <div id={@id} class="chat chat-end">
        <div class="chat-bubble bg-primary text-primary-content">
          {@message.content}
        </div>
        <div class="chat-footer text-xs opacity-50 mt-1">
          {format_time(@message.inserted_at)}
        </div>
      </div>
    <% else %>
      <!-- Lincoln message -->
      <div id={@id} class="chat chat-start">
        <div class="chat-image avatar">
          <div class="w-10 rounded-lg bg-secondary flex items-center justify-center">
            <span class="font-bold text-secondary-content">L</span>
          </div>
        </div>
        <div class="chat-bubble bg-base-200 text-base-content border border-base-300">
          <div class="whitespace-pre-wrap">{@message.content}</div>
          
    <!-- Thinking panel (minimal) -->
          <div
            class="mt-3 pt-2 border-t border-base-300 cursor-pointer hover:bg-base-300/50 -mx-3 -mb-2 px-3 pb-2 rounded-b-lg transition-colors"
            phx-click="expand_thinking"
            phx-value-id={@message.id}
          >
            <div class="flex items-center gap-2 text-xs text-base-content/60">
              <span title="Memories retrieved">
                <.icon name="hero-archive-box" class="w-3 h-3 inline" /> {@message.memories_retrieved}
              </span>
              <span class="text-base-content/30">|</span>
              <span title="Beliefs consulted">
                <.icon name="hero-light-bulb" class="w-3 h-3 inline" /> {@message.beliefs_consulted}
              </span>
              <%= if @message.beliefs_revised > 0 do %>
                <span class="text-base-content/30">|</span>
                <span class="text-warning" title="Beliefs revised">
                  <.icon name="hero-arrow-path" class="w-3 h-3 inline" /> {@message.beliefs_revised}
                </span>
              <% end %>
              <%= if @message.contradiction_detected do %>
                <span class="text-base-content/30">|</span>
                <span class="text-error" title="Contradiction detected">
                  <.icon name="hero-exclamation-triangle" class="w-3 h-3 inline" />
                </span>
              <% end %>
              <span class="flex-1"></span>
              <.icon
                name="hero-chevron-down"
                class={["w-3 h-3 transition-transform", @expanded && "rotate-180"]}
              />
            </div>
            
    <!-- Expanded details -->
            <div :if={@expanded} class="mt-2 text-xs space-y-1 text-base-content/70">
              <p :if={@message.thinking_summary} class="italic">
                {@message.thinking_summary}
              </p>
              <p :if={!@message.thinking_summary}>
                Retrieved {@message.memories_retrieved} memories, consulted {@message.beliefs_consulted} beliefs.
                <%= if @message.beliefs_formed > 0 do %>
                  Formed {@message.beliefs_formed} new belief(s).
                <% end %>
                <%= if @message.questions_generated > 0 do %>
                  Generated {@message.questions_generated} question(s).
                <% end %>
              </p>
            </div>
          </div>
        </div>
        <div class="chat-footer text-xs opacity-50 mt-1">
          {format_time(@message.inserted_at)}
        </div>
      </div>
    <% end %>
    """
  end

  attr(:step, :string, default: nil)

  defp thinking_indicator(assigns) do
    ~H"""
    <div class="chat chat-start p-4">
      <div class="chat-image avatar">
        <div class="w-10 rounded-lg bg-secondary/50 flex items-center justify-center animate-pulse">
          <span class="font-bold text-secondary-content">L</span>
        </div>
      </div>
      <div class="chat-bubble bg-base-200 border border-base-300">
        <div class="flex items-center gap-2 text-sm">
          <span class="loading loading-dots loading-sm"></span>
          <span class="text-base-content/60">{@step || "Thinking..."}</span>
        </div>
      </div>
    </div>
    """
  end

  attr(:value, :string, default: "")
  attr(:disabled, :boolean, default: false)

  defp chat_input(assigns) do
    ~H"""
    <footer class="border-t border-base-300 p-4 bg-base-200 shrink-0">
      <form id="chat-form" phx-submit="send_message" phx-change="input_change">
        <div class="flex gap-2">
          <input
            type="text"
            name="message"
            value={@value}
            placeholder="Type a message... (try 'research [topic]' or 'improve yourself')"
            disabled={@disabled}
            autocomplete="off"
            phx-debounce="100"
            class="input input-bordered flex-1 bg-base-100"
          />
          <button
            type="submit"
            class="btn btn-primary"
            disabled={@disabled || @value == ""}
            phx-disable-with="..."
          >
            <.icon name="hero-paper-airplane" class="w-5 h-5" />
          </button>
        </div>
      </form>
    </footer>
    """
  end

  attr(:show, :boolean, default: false)
  attr(:worker_events, :list, default: [])
  attr(:cognitive_events, :list, default: [])
  attr(:event_filter, :string, default: "all")
  attr(:active_session, :map, default: nil)

  defp worker_sidebar(assigns) do
    # Combine and filter events
    # Sort by timestamp descending - convert to unix for consistent sorting
    # since timestamps can be either DateTime or NaiveDateTime
    all_events =
      (assigns.worker_events ++ assigns.cognitive_events)
      |> Enum.sort_by(&timestamp_to_unix(&1.timestamp), :desc)

    filtered_events = filter_events(all_events, assigns.event_filter)

    assigns = assign(assigns, :filtered_events, filtered_events)
    assigns = assign(assigns, :all_events, all_events)

    ~H"""
    <aside class={[
      "w-72 bg-base-200 border-l border-base-300 flex flex-col",
      "fixed inset-y-0 right-0 z-40 transition-transform duration-200",
      "lg:relative lg:translate-x-0",
      if(@show, do: "translate-x-0", else: "translate-x-full lg:hidden")
    ]}>
      <div class="p-4 border-b border-base-300 flex items-center justify-between shrink-0">
        <h2 class="font-semibold text-sm flex items-center gap-2">
          <.icon name="hero-cpu-chip" class="w-4 h-4" /> Activity Feed
        </h2>
        <button phx-click="toggle_worker_sidebar" class="btn btn-ghost btn-xs btn-square lg:hidden">
          <.icon name="hero-x-mark" class="w-4 h-4" />
        </button>
      </div>
      
    <!-- Active Session Status -->
      <div :if={@active_session} class="p-3 bg-success/10 border-b border-base-300 shrink-0">
        <div class="flex items-center gap-2 text-xs">
          <span class="w-2 h-2 rounded-full bg-success animate-pulse"></span>
          <span class="uppercase text-success font-medium">Learning Active</span>
        </div>
        <p :if={@active_session.current_topic} class="text-xs mt-1 text-base-content/70 truncate">
          Exploring: {@active_session.current_topic}
        </p>
        <div class="flex gap-3 mt-2 text-xs text-base-content/50">
          <span title="Topics completed">
            <.icon name="hero-check-circle" class="w-3 h-3 inline" />
            {@active_session.topics_completed}/{@active_session.topics_total}
          </span>
          <span title="Beliefs formed">
            <.icon name="hero-light-bulb" class="w-3 h-3 inline" />
            {@active_session.beliefs_formed}
          </span>
        </div>
      </div>

      <div :if={@active_session == nil} class="p-3 bg-base-300/30 border-b border-base-300 shrink-0">
        <div class="flex items-center gap-2 text-xs text-base-content/50">
          <span class="w-2 h-2 rounded-full bg-warning"></span>
          <span class="uppercase">Idle</span>
        </div>
        <p class="text-xs mt-1 text-base-content/40">
          Say "research [topic]" to start learning
        </p>
      </div>
      
    <!-- Event Filters -->
      <div class="p-2 border-b border-base-300 shrink-0">
        <div class="flex flex-wrap gap-1">
          <.filter_button filter="all" current={@event_filter} count={length(@all_events)} />
          <.filter_button filter="struggles" current={@event_filter} />
          <.filter_button filter="learning" current={@event_filter} />
          <.filter_button filter="corrections" current={@event_filter} />
          <.filter_button filter="improvements" current={@event_filter} />
          <.filter_button filter="errors" current={@event_filter} />
        </div>
      </div>
      
    <!-- Event Feed -->
      <div class="flex-1 overflow-y-auto min-h-0">
        <div class="p-2 space-y-2">
          <%= if @filtered_events == [] do %>
            <div class="text-center text-xs text-base-content/40 py-8">
              <.icon name="hero-clock" class="w-6 h-6 mx-auto mb-2 opacity-50" />
              <p>No recent activity</p>
              <p class="mt-1">Events will appear here</p>
            </div>
          <% else %>
            <.combined_event :for={event <- @filtered_events} event={event} />
          <% end %>
        </div>
      </div>

      <div class="p-3 border-t border-base-300 text-xs text-base-content/40 shrink-0">
        <p>{length(@filtered_events)} of {length(@all_events)} events shown</p>
      </div>
    </aside>
    """
  end

  attr(:filter, :string, required: true)
  attr(:current, :string, required: true)
  attr(:count, :integer, default: nil)

  defp filter_button(assigns) do
    ~H"""
    <button
      phx-click="filter_events"
      phx-value-filter={@filter}
      class={[
        "btn btn-xs",
        if(@current == @filter, do: "btn-primary", else: "btn-ghost")
      ]}
    >
      {filter_label(@filter)}
      <span :if={@count} class="badge badge-xs">{@count}</span>
    </button>
    """
  end

  defp filter_label(filter) do
    case filter do
      "all" -> "All"
      "struggles" -> "Struggles"
      "learning" -> "Learning"
      "corrections" -> "Corrections"
      "improvements" -> "Changes"
      "errors" -> "Errors"
      _ -> filter
    end
  end

  defp filter_events(events, "all"), do: events

  defp filter_events(events, filter) do
    filter_types = Map.get(@event_filters, filter, [])

    Enum.filter(events, fn event ->
      # Worker events use atom types, cognitive events use string types
      event_type = if is_atom(event.type), do: Atom.to_string(event.type), else: event.type

      # Check if the event type matches the filter
      # Also match worker events by their category
      event_type in filter_types or
        worker_event_matches_filter?(event.type, filter)
    end)
  end

  defp worker_event_matches_filter?(type, filter) when is_atom(type) do
    case {type, filter} do
      {:session, _} -> true
      {:topic, "learning"} -> true
      {:evolution, "improvements"} -> true
      {:believe, "learning"} -> true
      {:memorize, "learning"} -> true
      {:reflect, "learning"} -> true
      {:code_change, "improvements"} -> true
      _ -> false
    end
  end

  defp worker_event_matches_filter?(_type, _filter), do: false

  attr(:event, :map, required: true)

  defp combined_event(assigns) do
    ~H"""
    <div class={["p-2 rounded-lg border text-xs", event_style(@event.type)]}>
      <div class="flex items-start gap-2">
        <.icon name={@event.icon} class="w-4 h-4 shrink-0 mt-0.5" />
        <div class="flex-1 min-w-0">
          <p class="font-medium truncate">{@event.message}</p>
          <p :if={@event.detail} class="text-base-content/60 truncate">{@event.detail}</p>
          <div class="flex items-center gap-2 mt-1">
            <span :if={@event[:severity]} class={["badge badge-xs", severity_badge(@event.severity)]}>
              {@event.severity}
            </span>
            <span class="text-base-content/40">{format_event_time(@event.timestamp)}</span>
          </div>
        </div>
      </div>
    </div>
    """
  end

  defp event_style(type) do
    case type do
      # Worker event types (atoms)
      :evolution -> "bg-secondary/10 border-secondary/30"
      :session -> "bg-primary/10 border-primary/30"
      :topic -> "bg-info/10 border-info/30"
      :believe -> "bg-warning/10 border-warning/30"
      :memorize -> "bg-accent/10 border-accent/30"
      :reflect -> "bg-success/10 border-success/30"
      :code_change -> "bg-secondary/10 border-secondary/30"
      # Cognitive event types (strings)
      "thought_loop_gave_up" -> "bg-error/10 border-error/30"
      "thought_loop_slow" -> "bg-warning/10 border-warning/30"
      "low_confidence_response" -> "bg-warning/10 border-warning/30"
      "user_correction" -> "bg-info/10 border-info/30"
      "knowledge_gap_detected" -> "bg-info/10 border-info/30"
      "belief_contradiction" -> "bg-error/10 border-error/30"
      "research_failed" -> "bg-error/10 border-error/30"
      "belief_formed" -> "bg-success/10 border-success/30"
      "belief_revised" -> "bg-warning/10 border-warning/30"
      "error_occurred" -> "bg-error/10 border-error/30"
      "slow_operation" -> "bg-warning/10 border-warning/30"
      "improvement_opportunity" -> "bg-primary/10 border-primary/30"
      "code_change_applied" -> "bg-secondary/10 border-secondary/30"
      "improvement_observed" -> "bg-success/10 border-success/30"
      _ -> "bg-base-300 border-base-content/10"
    end
  end

  defp severity_badge(severity) do
    case severity do
      "critical" -> "badge-error"
      "high" -> "badge-warning"
      "medium" -> "badge-info"
      "low" -> "badge-ghost"
      _ -> "badge-ghost"
    end
  end

  defp format_event_time(datetime) do
    now = DateTime.utc_now()
    # Handle both NaiveDateTime (from Ecto) and DateTime
    dt = ensure_datetime(datetime)
    diff = DateTime.diff(now, dt, :second)

    cond do
      diff < 60 -> "just now"
      diff < 3600 -> "#{div(diff, 60)}m ago"
      diff < 86400 -> "#{div(diff, 3600)}h ago"
      true -> Calendar.strftime(dt, "%b %d")
    end
  end

  defp ensure_datetime(%DateTime{} = dt), do: dt
  defp ensure_datetime(%NaiveDateTime{} = ndt), do: DateTime.from_naive!(ndt, "Etc/UTC")

  # Convert any datetime type to unix seconds for consistent sorting
  defp timestamp_to_unix(%DateTime{} = dt), do: DateTime.to_unix(dt, :second)

  defp timestamp_to_unix(%NaiveDateTime{} = ndt) do
    ndt |> DateTime.from_naive!("Etc/UTC") |> DateTime.to_unix(:second)
  end

  # ============================================================================
  # Helper Functions
  # ============================================================================

  defp format_time(datetime) do
    Calendar.strftime(datetime, "%I:%M %p")
  end
end
