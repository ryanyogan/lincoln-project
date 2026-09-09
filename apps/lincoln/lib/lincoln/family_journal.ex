defmodule Lincoln.FamilyJournal do
  @moduledoc "Original, attributed family writing. Append-only through this interface."
  import Ecto.Query
  import Ecto.Changeset
  alias Lincoln.{Memory, Repo}
  alias Lincoln.Memory.Memory, as: Entry

  @types ~w(story value preference correction)

  def changeset(params \\ %{}) do
    {%{}, %{author: :string, content: :string, kind: :string}}
    |> cast(params, [:author, :content, :kind])
    |> validate_required([:author, :content, :kind])
    |> validate_length(:author, max: 100)
    |> validate_length(:content, max: 20_000)
    |> validate_inclusion(:kind, @types)
  end

  def record(agent, params) do
    with {:ok, entry} <- apply_action(changeset(params), :insert) do
      Memory.create_memory(agent, %{
        content: entry.content,
        memory_type: "conversation",
        importance: 8,
        source_context: %{
          "origin" => "family_journal",
          "author" => entry.author,
          "kind" => entry.kind,
          "verbatim" => true
        }
      })
    end
  end

  def list(agent, opts \\ []) do
    query = query(agent.id)
    search = String.trim(Keyword.get(opts, :search, ""))

    query =
      if search == "",
        do: query,
        else: where(query, [e], fragment("strpos(lower(?), lower(?)) > 0", e.content, ^search))

    query
    |> order_by([e], desc: e.inserted_at, desc: e.id)
    |> limit(^Keyword.get(opts, :limit, 30))
    |> offset(^Keyword.get(opts, :offset, 0))
    |> Repo.all()
  end

  def export(agent) do
    entries = query(agent.id) |> order_by([e], asc: e.inserted_at, asc: e.id) |> Repo.all()

    %{
      format: "lincoln-family-journal",
      version: 1,
      exported_at: DateTime.utc_now(),
      entries: Enum.map(entries, &Map.take(&1, [:id, :content, :source_context, :inserted_at]))
    }
  end

  # The exact text remains in storage. Context is bounded and labels excerpts explicitly.
  def context(agent) do
    entries = list(agent, limit: 8)

    Enum.map_join(entries, "\n\n", fn entry ->
      Jason.encode!(%{
        journal_id: entry.id,
        author: entry.source_context["author"],
        kind: entry.source_context["kind"],
        recorded_at: entry.inserted_at,
        excerpt: String.slice(entry.content, 0, 1500),
        truncated: String.length(entry.content) > 1500
      })
    end)
  end

  defp query(agent_id) do
    from e in Entry,
      where: e.agent_id == ^agent_id,
      where: fragment("?->>'origin' = 'family_journal'", e.source_context)
  end
end
