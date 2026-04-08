# Lincoln: Theory of Mind — User Models (Step 4)

## TL;DR

> **Quick Summary**: Add a `user_models` table tracking what Lincoln believes about the person it's talking with — their recurring topics, question patterns, vocabulary style, and engagement history. The ConversationBridge populates it on each message. The chat LiveView shows a "what Lincoln knows about you" panel.
>
> **Deliverables**:
> - `user_models` table (migration + schema)
> - `Lincoln.UserModels` context: `observe_message/3`, `get_model/2`, `to_context_string/1`
> - ConversationBridge updated to call `observe_message/3` on each user message
> - Chat LiveView gets a "User Model" panel showing what Lincoln has inferred
>
> **Estimated Effort**: Small (1 day)
> **Parallel Execution**: NO — sequential
> **Critical Path**: Migration → Context → Bridge hook → Dashboard panel

---

## Context

The master plan: *"Add a `user_models` table that tracks what Lincoln believes about the user it's talking to — what they know, what they care about, what confuses them, what they've asked for repeatedly. When the Driver is responding to a user, consult the user model. This is a one-day feature and it closes a real gap vs Sophia."*

Sophia explicitly models its conversation partner (Theory of Mind is in the Sophia paper as a named capability). Lincoln having no user model is a gap.

For v1: JSONB-backed model with topic tracking + message stats. No ML extraction — simple keyword accumulation. The gap closes the Sophia comparison.

---

## TODOs

- [x] 1. Migration + Schema + Context

  **Migration** — run `mix ecto.gen.migration create_user_models` then:
  ```elixir
  create table(:user_models, primary_key: false) do
    add :id, :binary_id, primary_key: true, default: fragment("gen_random_uuid()")
    add :agent_id, references(:agents, type: :binary_id, on_delete: :delete_all), null: false
    add :session_id, :string, null: false  # conversation or session identifier
    add :message_count, :integer, default: 0
    add :question_count, :integer, default: 0
    add :topics, {:array, :string}, default: []  # recurring topics extracted from messages
    add :vocabulary_style, :string, default: "unknown"  # "technical" | "casual" | "mixed" | "unknown"
    add :first_seen_at, :utc_datetime
    add :last_seen_at, :utc_datetime
    add :model_data, :map, default: %{}  # flexible JSONB for future extension
    timestamps(type: :utc_datetime)
  end
  create unique_index(:user_models, [:agent_id, :session_id])
  create index(:user_models, [:agent_id])
  ```

  **Schema** — `lib/lincoln/user_models/user_model.ex`:
  ```elixir
  defmodule Lincoln.UserModels.UserModel do
    use Ecto.Schema
    import Ecto.Changeset

    @primary_key {:id, :binary_id, autogenerate: true}
    @foreign_key_type :binary_id

    schema "user_models" do
      field :session_id, :string
      field :message_count, :integer, default: 0
      field :question_count, :integer, default: 0
      field :topics, {:array, :string}, default: []
      field :vocabulary_style, :string, default: "unknown"
      field :first_seen_at, :utc_datetime
      field :last_seen_at, :utc_datetime
      field :model_data, :map, default: %{}
      belongs_to :agent, Lincoln.Agents.Agent
      timestamps(type: :utc_datetime)
    end

    def changeset(model, attrs) do
      model
      |> cast(attrs, [:session_id, :message_count, :question_count, :topics,
                      :vocabulary_style, :first_seen_at, :last_seen_at, :model_data, :agent_id])
      |> validate_required([:session_id, :agent_id])
      |> unique_constraint([:agent_id, :session_id])
    end
  end
  ```

  **Context** — `lib/lincoln/user_models.ex`:
  ```elixir
  defmodule Lincoln.UserModels do
    import Ecto.Query
    alias Lincoln.{Repo, Agents}
    alias Lincoln.Agents.Agent
    alias Lincoln.UserModels.UserModel

    @doc "Get or create a user model for this agent + session."
    def get_or_create_model(agent_id, session_id) when is_binary(agent_id) and is_binary(session_id) do
      case Repo.get_by(UserModel, agent_id: agent_id, session_id: session_id) do
        nil ->
          %UserModel{}
          |> UserModel.changeset(%{
            agent_id: agent_id,
            session_id: session_id,
            first_seen_at: DateTime.utc_now(),
            last_seen_at: DateTime.utc_now()
          })
          |> Repo.insert()
        model ->
          {:ok, model}
      end
    end

    @doc "Get user model (returns nil if not found)."
    def get_model(agent_id, session_id) do
      Repo.get_by(UserModel, agent_id: agent_id, session_id: session_id)
    end

    @doc """
    Observe a user message and update the model.
    Extracts topics, increments counters, updates vocabulary style.
    """
    def observe_message(agent_id, session_id, message_content) when is_binary(message_content) do
      with {:ok, model} <- get_or_create_model(agent_id, session_id) do
        extracted = extract_features(message_content)
        is_question = String.contains?(message_content, "?")

        new_topics =
          (model.topics ++ extracted.topics)
          |> Enum.uniq()
          |> Enum.take(20)  # cap at 20 topics

        style = infer_style(message_content, model.vocabulary_style)

        model
        |> UserModel.changeset(%{
          message_count: model.message_count + 1,
          question_count: model.question_count + (if is_question, do: 1, else: 0),
          topics: new_topics,
          vocabulary_style: style,
          last_seen_at: DateTime.utc_now()
        })
        |> Repo.update()
      end
    end

    @doc "Convert user model to a context string for LLM prompts."
    def to_context_string(%UserModel{} = model) do
      topics_str = if model.topics == [], do: "none detected yet", else: Enum.join(model.topics, ", ")
      style = model.vocabulary_style || "unknown"
      q_ratio = if model.message_count > 0,
        do: Float.round(model.question_count / model.message_count * 100),
        else: 0

      """
      User context (#{model.message_count} messages in this session):
      - Topics of interest: #{topics_str}
      - Vocabulary style: #{style}
      - Question ratio: #{q_ratio}%
      """
    end

    def to_context_string(nil), do: ""

    # ── Private ────────────────────────────────────────────────────────────────

    defp extract_features(text) do
      # Simple keyword extraction: words > 5 chars, not common stop words, downcased
      stop_words = ~w(about after again against before being between could during every
                      itself might other should their there these those through under
                      which while would without)

      topics =
        text
        |> String.downcase()
        |> String.replace(~r/[^a-z0-9\s]/, " ")
        |> String.split()
        |> Enum.filter(fn w -> String.length(w) > 4 and w not in stop_words end)
        |> Enum.uniq()
        |> Enum.take(5)

      %{topics: topics}
    end

    defp infer_style(text, current_style) do
      # Simple heuristic: presence of technical terms
      technical_markers = ~w(function module process genserver ecto migration
                             elixir erlang otp beam api database schema query
                             algorithm architecture substrate cognition)
      words = text |> String.downcase() |> String.split()
      tech_count = Enum.count(words, fn w -> w in technical_markers end)

      cond do
        tech_count >= 2 -> "technical"
        tech_count == 1 and current_style == "technical" -> "technical"
        current_style in ["technical", "casual"] -> current_style
        true -> "casual"
      end
    end
  end
  ```

  **Recommended Agent Profile**: `quick`
  **Commit**: `feat(tom): add user_models table, schema, and context`

- [x] 2. Hook ConversationBridge + Chat LiveView Panel

  **Two changes in one task:**

  **A. Update ConversationBridge** (`lib/lincoln/substrate/conversation_bridge.ex`):
  Add `observe_message` call when notifying substrate:
  ```elixir
  def notify(agent_id, message, cognitive_metadata \\ %{}) do
    # Extract session_id from metadata (conversation_id is the best proxy)
    session_id = Map.get(cognitive_metadata, :conversation_id) ||
                 Map.get(cognitive_metadata, "conversation_id") ||
                 "default"

    # Observe the message for theory of mind
    user_content = Map.get(cognitive_metadata, :user_content) ||
                   Map.get(cognitive_metadata, "user_content") ||
                   ""

    if String.length(user_content) > 0 do
      Task.start(fn ->
        try do
          Lincoln.UserModels.observe_message(agent_id, session_id, user_content)
        rescue
          e -> Logger.warning("[ConversationBridge] UserModel update failed: #{Exception.message(e)}")
        end
      end)
    end

    # Existing substrate event notification
    event = %{
      type: :conversation,
      content: message,
      metadata: cognitive_metadata,
      occurred_at: DateTime.utc_now()
    }
    case Substrate.send_event(agent_id, event) do
      :ok -> :ok
      {:error, :not_running} -> :ok
    end
  end
  ```

  **Also update the chat_live.ex call site**: Pass `user_content` in the cognitive_metadata so ConversationBridge can see it. Find where `ConversationBridge.notify/3` is called and add the user message content to the metadata map.

  **B. Chat LiveView user model panel** — add to `chat_live.ex` a small panel showing:
  ```
  What Lincoln knows about you:
  Topics: elixir, substrate, cognition...
  Style: technical
  Questions asked: 4/7 messages
  ```

  If the current chat_live.ex is complex, add a small sidebar widget rather than modifying the main layout.

  **Recommended Agent Profile**: `deep`
  **Commit**: `feat(tom): wire user model into ConversationBridge and show in chat`

---

## Definition of Done
- [ ] `mix ecto.migrate` runs clean (when DB is available)
- [ ] `Lincoln.UserModels.observe_message(agent_id, "session-1", "How does the BEAM handle concurrency?")` inserts/updates a model
- [ ] `Lincoln.UserModels.get_model(agent_id, "session-1")` returns the model with topics populated
- [ ] `Lincoln.UserModels.to_context_string(model)` returns a readable summary
- [ ] ConversationBridge fires the observe_message on each user message
- [ ] `mix compile --warnings-as-errors` passes
