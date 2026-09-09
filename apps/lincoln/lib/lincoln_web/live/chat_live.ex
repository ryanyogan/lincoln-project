defmodule LincolnWeb.ChatLive do
  @moduledoc "Conversation first, with history and response context available on demand."
  use LincolnWeb, :live_view

  alias Lincoln.{Agents, Conversation}
  alias Lincoln.Cognition.ConversationHandler
  alias Lincoln.Substrate.ConversationBridge

  @impl true
  def mount(_params, _session, socket) do
    {:ok, agent} = Agents.get_or_create_default_agent()

    {:ok,
     socket
     |> assign(agent: agent, page_title: "Talk", conversation: nil, processing: false)
     |> assign(conversations: Conversation.list_conversations(agent.id, limit: 30))
     |> assign(form: to_form(%{"message" => ""}), message_count: 0)
     |> stream(:messages, [])}
  end

  @impl true
  def handle_params(%{"id" => id}, _uri, socket) do
    conversation = Conversation.get_conversation_with_messages(id)

    if conversation.agent_id == socket.assigns.agent.id do
      {:noreply,
       socket
       |> assign(conversation: conversation, message_count: length(conversation.messages))
       |> stream(:messages, conversation.messages, reset: true)}
    else
      {:noreply,
       socket |> put_flash(:error, "Conversation not found.") |> push_navigate(to: ~p"/")}
    end
  rescue
    Ecto.NoResultsError ->
      {:noreply,
       socket |> put_flash(:error, "Conversation not found.") |> push_navigate(to: ~p"/")}

    Ecto.Query.CastError ->
      {:noreply,
       socket |> put_flash(:error, "Conversation not found.") |> push_navigate(to: ~p"/")}
  end

  def handle_params(_params, _uri, socket), do: {:noreply, socket}

  @impl true
  def handle_event("input_change", params, socket) do
    {:noreply, assign(socket, :form, to_form(params))}
  end

  def handle_event("send_message", %{"message" => content}, socket) do
    if socket.assigns.processing or String.trim(content) == "" do
      {:noreply, socket}
    else
      conversation = socket.assigns.conversation || create_conversation(socket.assigns.agent.id)
      {:ok, message} = Conversation.add_user_message(conversation.id, content)
      agent_id = socket.assigns.agent.id

      {:noreply,
       socket
       |> assign(conversation: conversation, processing: true, form: to_form(%{"message" => ""}))
       |> update(:message_count, &(&1 + 1))
       |> stream_insert(:messages, message)
       |> start_async(:response, fn ->
         result = ConversationHandler.process_message(agent_id, conversation.id, content)
         {result, conversation.id, content}
       end)}
    end
  end

  @impl true
  def handle_async(:response, {:ok, {{:ok, result}, conversation_id, content}}, socket) do
    metadata =
      result.cognitive_metadata
      |> Map.put(:conversation_id, conversation_id)
      |> Map.put(:user_content, content)

    ConversationBridge.notify(socket.assigns.agent.id, result.response, metadata)

    {:ok, message} =
      Conversation.add_assistant_message(
        conversation_id,
        result.response,
        result.cognitive_metadata
      )

    {:noreply,
     socket
     |> stream_insert(:messages, message)
     |> update(:message_count, &(&1 + 1))
     |> assign(processing: false)
     |> assign(
       :conversations,
       Conversation.list_conversations(socket.assigns.agent.id, limit: 30)
     )}
  end

  def handle_async(:response, _failure, socket) do
    {:noreply,
     socket
     |> assign(processing: false)
     |> put_flash(
       :error,
       "Lincoln couldn’t finish that reply. Your message is saved; you can try again."
     )}
  end

  defp create_conversation(agent_id) do
    {:ok, conversation} = Conversation.create_conversation(agent_id)
    conversation
  end

  @impl true
  def render(assigns) do
    assigns =
      assign(
        assigns,
        :local_inference_only,
        Application.get_env(:lincoln, :local_inference_only, false)
      )

    ~H"""
    <Layouts.app flash={@flash} current_path={@current_path}>
      <section class="talk-page" aria-label="Conversation with Lincoln">
        <header class="talk-toolbar">
          <span class="eyebrow">A little more understood, every day</span>
          <details id="conversation-history" class="history-menu">
            <summary><.icon name="hero-clock" class="size-4" /> Past conversations</summary>
            <div>
              <.link navigate={~p"/chat"} class="text-link">Start a new conversation</.link>
              <p :if={@conversations == []} class="muted">Your conversations will appear here.</p>
              <.link :for={conversation <- @conversations} navigate={~p"/chat/#{conversation.id}"}>
                {conversation.title || "Untitled conversation"}
              </.link>
            </div>
          </details>
        </header>
        <div :if={@message_count == 0} class="talk-welcome" id="talk-welcome">
          <span class="welcome-mark" aria-hidden="true">l.</span>
          <h1>What’s on your mind?</h1>
          <p>The everyday things. The big questions.<br />The stories you want to keep.</p>
          <.link navigate={~p"/journal"} class="text-link">
            Leave something in the family journal <span aria-hidden="true">↗</span>
          </.link>
        </div>
        <div
          id="lincoln-messages"
          phx-hook="ScrollToBottom"
          class="conversation-scroll"
          role="log"
          aria-label="Messages"
          aria-live="polite"
        >
          <div id="messages-stream" phx-update="stream" class="message-list">
            <article
              :for={{dom_id, message} <- @streams.messages}
              id={dom_id}
              class={["message", message.role == "user" && "message-user"]}
            >
              <p class="message-author">{if message.role == "user", do: "You", else: "Lincoln"}</p>
              <div class="message-content">{message.content}</div>
              <details :if={message.role == "assistant"} class="response-context">
                <summary>About this reply</summary>
                <p>
                  Consulted {message.memories_retrieved || 0} memories and {message.beliefs_consulted ||
                    0} beliefs. This is a generated response.
                </p>
              </details>
            </article>
          </div>
        </div>
        <p :if={@processing} id="response-pending" class="pending-reply" role="status">
          Lincoln is considering your message…
        </p>
        <.form
          for={@form}
          id="chat-form"
          phx-submit="send_message"
          phx-change="input_change"
          class="talk-composer"
        >
          <.input
            field={@form[:message]}
            type="textarea"
            label="Your message"
            placeholder="Tell me what’s on your mind…"
            rows="2"
            disabled={@processing}
            class="family-input composer-input"
          />
          <button
            type="submit"
            class="family-button"
            disabled={@processing}
            phx-disable-with="Sending…"
          >
            Send <.icon name="hero-arrow-up" class="size-4" />
          </button>
        </.form>
        <p class="composer-note">
          <%= if @local_inference_only do %>
            Local model configured. Original family stories live in your journal.
          <% else %>
            Cloud model configured. Messages and relevant journal entries may be sent to your model provider.
          <% end %>
        </p>
      </section>
    </Layouts.app>
    """
  end
end
