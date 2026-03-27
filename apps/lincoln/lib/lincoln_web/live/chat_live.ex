defmodule LincolnWeb.ChatLive do
  @moduledoc """
  Main chat interface with cognitive transparency and optional baseline comparison.

  Features:
  - Split view: Lincoln (with thinking) vs Claude baseline (optional)
  - Conversation history sidebar
  - Real-time cognitive process display
  - Mobile responsive
  """
  use LincolnWeb, :live_view

  alias Lincoln.{Agents, Conversation}
  alias Lincoln.Cognition.ConversationHandler

  @impl true
  def mount(_params, _session, socket) do
    {:ok, agent} = Agents.get_or_create_default_agent()
    conversations = Conversation.list_conversations(agent.id, limit: 20)

    socket =
      socket
      |> assign(:agent, agent)
      |> assign(:page_title, "Chat")
      |> assign(:conversations, conversations)
      |> assign(:conversation, nil)
      |> assign(:input, "")
      |> assign(:show_baseline, false)
      |> assign(:show_sidebar, false)
      |> assign(:processing, false)
      |> assign(:thinking_step, nil)
      |> assign(:expanded_thinking, nil)
      |> stream(:messages, [])

    if connected?(socket) do
      Phoenix.PubSub.subscribe(Lincoln.PubSub, "agent:#{agent.id}:chat")
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

  def handle_event("toggle_baseline", _params, socket) do
    {:noreply, assign(socket, :show_baseline, !socket.assigns.show_baseline)}
  end

  def handle_event("toggle_sidebar", _params, socket) do
    {:noreply, assign(socket, :show_sidebar, !socket.assigns.show_sidebar)}
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

  # ============================================================================
  # Async Message Handling
  # ============================================================================

  @impl true
  def handle_info({:process_message, content}, socket) do
    agent = socket.assigns.agent
    conversation = socket.assigns.conversation
    show_baseline = socket.assigns.show_baseline

    result =
      ConversationHandler.process_message(
        agent.id,
        conversation.id,
        content,
        include_baseline: show_baseline
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
              thinking_summary: cognitive_result.cognitive_metadata.thinking_summary,
              baseline_response: cognitive_result.baseline_response
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
      <div class="h-[calc(100vh-12rem)] flex relative">
        <!-- Mobile sidebar overlay -->
        <div
          :if={@show_sidebar}
          class="fixed inset-0 bg-black/50 z-30 lg:hidden"
          phx-click="toggle_sidebar"
        >
        </div>
        
    <!-- Conversation Sidebar -->
        <.conversation_sidebar
          conversations={@conversations}
          current={@conversation}
          show={@show_sidebar}
        />
        
    <!-- Main Chat Area -->
        <div class="flex-1 flex flex-col min-w-0 bg-base-100">
          <!-- Chat Header -->
          <.chat_header
            conversation={@conversation}
            show_baseline={@show_baseline}
          />
          
    <!-- Messages Area -->
          <div class="flex-1 overflow-hidden">
            <div class={[
              "h-full flex",
              @show_baseline && "divide-x-2 divide-primary/20"
            ]}>
              <!-- Lincoln Column -->
              <div class={["flex-1 flex flex-col min-w-0", @show_baseline && "max-w-1/2"]}>
                <div
                  :if={@show_baseline}
                  class="px-4 py-2 border-b border-primary/20 bg-base-200"
                >
                  <div class="flex items-center gap-2 text-xs font-terminal uppercase text-primary">
                    <.icon name="hero-cpu-chip" class="size-4" /> Lincoln (Learning Agent)
                  </div>
                </div>
                <div
                  class="flex-1 overflow-y-auto scroll-smooth"
                  id="lincoln-messages"
                  phx-hook="ScrollToBottom"
                >
                  <div id="messages-stream" phx-update="stream" class="space-y-4 p-4">
                    <!-- Empty state -->
                    <div class="hidden only:flex flex-col items-center justify-center h-full text-center p-8">
                      <div class="avatar placeholder mb-4">
                        <div class="bg-primary text-primary-content w-16 border-2 border-primary shadow-brutal">
                          <span class="text-2xl font-black font-terminal">L</span>
                        </div>
                      </div>
                      <h2 class="font-terminal font-bold uppercase text-lg mb-2">
                        Start a Conversation
                      </h2>
                      <p class="text-sm text-base-content/60 max-w-sm">
                        Talk to Lincoln and watch him learn. He remembers conversations, forms beliefs, and can revise his understanding based on new evidence.
                      </p>
                    </div>
                    
    <!-- Messages -->
                    <.message_bubble
                      :for={{dom_id, msg} <- @streams.messages}
                      id={dom_id}
                      message={msg}
                      expanded={@expanded_thinking == msg.id}
                      column={:lincoln}
                    />
                  </div>
                  
    <!-- Thinking indicator -->
                  <.thinking_indicator :if={@processing} step={@thinking_step} />
                </div>
              </div>
              
    <!-- Baseline Column (optional) -->
              <div :if={@show_baseline} class="flex-1 flex flex-col min-w-0 bg-base-200/30">
                <div class="px-4 py-2 border-b border-primary/20 bg-base-200">
                  <div class="flex items-center gap-2 text-xs font-terminal uppercase text-base-content/50">
                    <.icon name="hero-cube" class="size-4" /> Claude (Stateless)
                  </div>
                </div>
                <div class="flex-1 overflow-y-auto">
                  <div class="space-y-4 p-4">
                    <.message_bubble
                      :for={{dom_id, msg} <- @streams.messages}
                      id={"baseline-#{dom_id}"}
                      message={msg}
                      column={:baseline}
                    />
                  </div>
                </div>
              </div>
            </div>
          </div>
          
    <!-- Input Area -->
          <.chat_input value={@input} disabled={@processing} />
        </div>
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
      "w-64 bg-base-200 border-r-2 border-primary flex flex-col",
      "fixed inset-y-0 left-0 z-40 transition-transform duration-200",
      "lg:relative lg:translate-x-0",
      if(@show, do: "translate-x-0", else: "-translate-x-full")
    ]}>
      <div class="p-4 border-b-2 border-primary flex items-center justify-between">
        <h2 class="font-terminal font-bold uppercase text-sm">History</h2>
        <button phx-click="new_conversation" class="btn btn-primary btn-xs gap-1">
          <.icon name="hero-plus" class="size-3" /> New
        </button>
      </div>

      <div class="flex-1 overflow-y-auto">
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
                  "font-terminal text-sm justify-start",
                  @current && @current.id == conv.id && "active"
                ]}
              >
                <.icon name="hero-chat-bubble-left-right" class="size-4 shrink-0" />
                <span class="truncate flex-1 text-left">{conv.title || "Untitled"}</span>
                <span class="badge badge-xs badge-ghost">{conv.message_count}</span>
              </button>
            </li>
          <% end %>
        </ul>
      </div>

      <div class="p-4 border-t border-primary/20 text-xs font-terminal text-base-content/40">
        <div class="flex items-center gap-2">
          <span class="status status-success neural-pulse"></span> Learning Active
        </div>
      </div>
    </aside>
    """
  end

  attr(:conversation, :map, default: nil)
  attr(:show_baseline, :boolean, default: false)

  defp chat_header(assigns) do
    ~H"""
    <div class="flex items-center justify-between p-4 border-b-2 border-primary bg-base-200">
      <div class="flex items-center gap-3">
        <!-- Mobile sidebar toggle -->
        <button phx-click="toggle_sidebar" class="btn btn-ghost btn-sm btn-square lg:hidden">
          <.icon name="hero-bars-3" class="size-5" />
        </button>

        <div class="avatar placeholder">
          <div class="bg-primary text-primary-content w-10 border-2 border-primary shadow-brutal-sm">
            <span class="font-terminal font-bold">L</span>
          </div>
        </div>
        <div>
          <h1 class="font-terminal font-bold uppercase">Lincoln</h1>
          <p class="text-xs font-terminal text-base-content/60">
            {if @conversation, do: @conversation.title || "New conversation", else: "Start chatting"}
          </p>
        </div>
      </div>

      <div class="flex items-center gap-2">
        <!-- Baseline toggle -->
        <label class="label cursor-pointer gap-2 hidden sm:flex">
          <span class="label-text text-xs font-terminal uppercase">Compare</span>
          <input
            type="checkbox"
            class="toggle toggle-primary toggle-sm"
            checked={@show_baseline}
            phx-click="toggle_baseline"
          />
        </label>
        
    <!-- Mobile baseline toggle -->
        <button
          phx-click="toggle_baseline"
          class={[
            "btn btn-sm btn-square sm:hidden",
            if(@show_baseline, do: "btn-primary", else: "btn-ghost")
          ]}
          title="Compare with baseline"
        >
          <.icon name="hero-square-2-stack" class="size-4" />
        </button>
        
    <!-- New chat button -->
        <button phx-click="new_conversation" class="btn btn-outline btn-primary btn-sm gap-1">
          <.icon name="hero-plus" class="size-4" />
          <span class="hidden sm:inline">New</span>
        </button>
      </div>
    </div>
    """
  end

  attr(:id, :string, required: true)
  attr(:message, :map, required: true)
  attr(:expanded, :boolean, default: false)
  attr(:column, :atom, values: [:lincoln, :baseline], default: :lincoln)

  defp message_bubble(assigns) do
    ~H"""
    <%= if @column == :lincoln do %>
      <%= if @message.role == "user" do %>
        <!-- User message -->
        <div id={@id} class="chat chat-end">
          <div class="chat-bubble bg-primary text-primary-content border-2 border-primary shadow-brutal-sm">
            {@message.content}
          </div>
          <div class="chat-footer text-xs font-terminal opacity-50 mt-1">
            {format_time(@message.inserted_at)}
          </div>
        </div>
      <% else %>
        <!-- Lincoln message -->
        <div id={@id} class="chat chat-start">
          <div class="chat-image avatar placeholder">
            <div class="bg-secondary text-secondary-content w-10 border-2 border-secondary">
              <span class="font-terminal font-bold">L</span>
            </div>
          </div>
          <div class="chat-bubble bg-base-200 border-2 border-secondary text-base-content shadow-brutal-sm">
            <div class="whitespace-pre-wrap">{@message.content}</div>
            
    <!-- Thinking panel (minimal) -->
            <div
              class="mt-3 pt-2 border-t border-secondary/30 cursor-pointer hover:bg-base-300/50 -mx-3 -mb-2 px-3 pb-2 transition-colors"
              phx-click="expand_thinking"
              phx-value-id={@message.id}
            >
              <div class="flex items-center gap-2 text-xs font-terminal text-base-content/60">
                <span title="Memories retrieved">
                  <.icon name="hero-archive-box" class="size-3 inline" /> {@message.memories_retrieved}
                </span>
                <span class="text-base-content/30">|</span>
                <span title="Beliefs consulted">
                  <.icon name="hero-light-bulb" class="size-3 inline" /> {@message.beliefs_consulted}
                </span>
                <%= if @message.beliefs_revised > 0 do %>
                  <span class="text-base-content/30">|</span>
                  <span class="text-warning" title="Beliefs revised">
                    <.icon name="hero-arrow-path" class="size-3 inline" /> {@message.beliefs_revised}
                  </span>
                <% end %>
                <%= if @message.contradiction_detected do %>
                  <span class="text-base-content/30">|</span>
                  <span class="text-error" title="Contradiction detected">
                    <.icon name="hero-exclamation-triangle" class="size-3 inline" />
                  </span>
                <% end %>
                <span class="flex-1"></span>
                <.icon
                  name="hero-chevron-down"
                  class={["size-3 transition-transform", @expanded && "rotate-180"]}
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
          <div class="chat-footer text-xs font-terminal opacity-50 mt-1">
            {format_time(@message.inserted_at)}
          </div>
        </div>
      <% end %>
    <% else %>
      <!-- Baseline column - show user messages and baseline responses -->
      <%= if @message.role == "user" do %>
        <div id={@id} class="chat chat-end">
          <div class="chat-bubble bg-base-300 text-base-content/70 border border-base-content/20">
            {@message.content}
          </div>
        </div>
      <% else %>
        <div id={@id} class="chat chat-start">
          <div class="chat-image avatar placeholder">
            <div class="bg-base-300 text-base-content/50 w-10 border border-base-content/20">
              <span class="font-terminal text-sm">C</span>
            </div>
          </div>
          <div class="chat-bubble bg-base-300/50 border border-base-content/20 text-base-content/70">
            <%= if @message.baseline_response do %>
              <div class="whitespace-pre-wrap">{@message.baseline_response}</div>
            <% else %>
              <span class="italic text-base-content/40">No baseline captured</span>
            <% end %>
          </div>
        </div>
      <% end %>
    <% end %>
    """
  end

  attr(:step, :string, default: nil)

  defp thinking_indicator(assigns) do
    ~H"""
    <div class="chat chat-start p-4">
      <div class="chat-image avatar placeholder">
        <div class="bg-secondary text-secondary-content w-10 border-2 border-secondary animate-pulse">
          <span class="font-terminal font-bold">L</span>
        </div>
      </div>
      <div class="chat-bubble bg-base-200 border-2 border-secondary/50">
        <div class="flex items-center gap-2 text-sm">
          <span class="loading loading-dots loading-sm"></span>
          <span class="font-terminal text-base-content/60">
            {@step || "Thinking..."}
          </span>
        </div>
      </div>
    </div>
    """
  end

  attr(:value, :string, default: "")
  attr(:disabled, :boolean, default: false)

  defp chat_input(assigns) do
    ~H"""
    <form
      phx-submit="send_message"
      phx-change="input_change"
      class="p-4 border-t-2 border-primary bg-base-200"
    >
      <div class="flex gap-2">
        <input
          type="text"
          name="message"
          value={@value}
          placeholder="Type a message..."
          disabled={@disabled}
          autocomplete="off"
          phx-debounce="100"
          class="input input-bordered input-primary flex-1 font-terminal bg-base-100"
        />
        <button
          type="submit"
          class="btn btn-primary"
          disabled={@disabled || @value == ""}
        >
          <.icon name="hero-paper-airplane" class="size-5" />
        </button>
      </div>
    </form>
    """
  end

  # ============================================================================
  # Helper Functions
  # ============================================================================

  defp format_time(datetime) do
    Calendar.strftime(datetime, "%I:%M %p")
  end
end
