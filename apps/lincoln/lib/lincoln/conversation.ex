defmodule Lincoln.Conversation do
  @moduledoc """
  Context for managing conversations and messages.

  Conversations are threaded chat sessions with an agent.
  Messages track both user input and Lincoln's responses,
  including cognitive metadata about what Lincoln was "thinking".

  ## Memory Strategy

  Each message is stored individually (raw), but Lincoln also creates
  synthesized memories from conversations:
  - Observation memories from user statements
  - Conversation memories from the exchange
  - Reflection memories when patterns are detected
  """

  import Ecto.Query, warn: false

  alias Lincoln.Repo
  alias Lincoln.Conversation.{Conversation, Message}

  # ============================================================================
  # Conversation Functions
  # ============================================================================

  @doc """
  Creates a new conversation for an agent.
  """
  def create_conversation(agent_id, attrs \\ %{}) do
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    %Conversation{}
    |> Conversation.changeset(
      Map.merge(attrs, %{
        agent_id: agent_id,
        started_at: now,
        last_message_at: now
      })
    )
    |> Repo.insert()
  end

  @doc """
  Gets a conversation by ID.
  """
  def get_conversation!(id) do
    Repo.get!(Conversation, id)
  end

  @doc """
  Gets a conversation with its messages, ordered by time.
  """
  def get_conversation_with_messages(id, limit \\ 100) do
    conversation = Repo.get!(Conversation, id)

    messages =
      Message
      |> where([m], m.conversation_id == ^id)
      |> order_by([m], asc: m.inserted_at)
      |> limit(^limit)
      |> Repo.all()

    %{conversation | messages: messages}
  end

  @doc """
  Lists conversations for an agent, most recent first.
  """
  def list_conversations(agent_id, opts \\ []) do
    limit = Keyword.get(opts, :limit, 20)

    Conversation
    |> where([c], c.agent_id == ^agent_id)
    |> order_by([c], desc: c.last_message_at)
    |> limit(^limit)
    |> Repo.all()
  end

  @doc """
  Updates conversation metadata.
  """
  def update_conversation(%Conversation{} = conversation, attrs) do
    conversation
    |> Conversation.changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Increments message count and updates last_message_at.
  """
  def touch_conversation(%Conversation{} = conversation) do
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    conversation
    |> Conversation.changeset(%{
      message_count: conversation.message_count + 1,
      last_message_at: now
    })
    |> Repo.update()
  end

  @doc """
  Generates a title for a conversation based on its first message.
  """
  def generate_title(content) when is_binary(content) do
    content
    |> String.slice(0, 50)
    |> String.trim()
    |> then(fn title ->
      if String.length(content) > 50, do: title <> "...", else: title
    end)
  end

  # ============================================================================
  # Message Functions
  # ============================================================================

  @doc """
  Adds a user message to a conversation.
  """
  def add_user_message(conversation_id, content) do
    add_message(conversation_id, %{
      role: "user",
      content: content
    })
  end

  @doc """
  Adds an assistant (Lincoln) message with cognitive metadata.
  """
  def add_assistant_message(conversation_id, content, cognitive_metadata \\ %{}) do
    add_message(
      conversation_id,
      Map.merge(cognitive_metadata, %{
        role: "assistant",
        content: content
      })
    )
  end

  @doc """
  Adds a message to a conversation.
  """
  def add_message(conversation_id, attrs) do
    conversation = get_conversation!(conversation_id)

    result =
      %Message{}
      |> Message.changeset(Map.put(attrs, :conversation_id, conversation_id))
      |> Repo.insert()

    case result do
      {:ok, message} ->
        # Update conversation metadata
        touch_conversation(conversation)

        # Set title from first user message if not set
        if is_nil(conversation.title) and attrs[:role] == "user" do
          update_conversation(conversation, %{title: generate_title(attrs[:content])})
        end

        {:ok, message}

      error ->
        error
    end
  end

  @doc """
  Gets recent messages for context window.
  """
  def get_recent_messages(conversation_id, limit \\ 20) do
    Message
    |> where([m], m.conversation_id == ^conversation_id)
    |> order_by([m], desc: m.inserted_at)
    |> limit(^limit)
    |> Repo.all()
    |> Enum.reverse()
  end

  @doc """
  Gets a specific message.
  """
  def get_message!(id) do
    Repo.get!(Message, id)
  end

  @doc """
  Updates a message (e.g., to add baseline response).
  """
  def update_message(%Message{} = message, attrs) do
    message
    |> Message.changeset(attrs)
    |> Repo.update()
  end
end
