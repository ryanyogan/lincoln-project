defmodule Lincoln.Autonomy.WebSource do
  @moduledoc """
  Schema for web sources that Lincoln has fetched and read.

  Tracks URLs visited, content summaries, and quality assessments.
  Used to avoid re-fetching the same content and to attribute
  beliefs to their sources.
  """
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  @fetch_statuses ~w(success failed blocked timeout)

  schema "web_sources" do
    field(:url, :string)
    field(:title, :string)
    field(:domain, :string)
    field(:content_summary, :string)
    field(:content_length, :integer)
    field(:facts_extracted, :integer, default: 0)
    field(:quality_score, :float)
    field(:fetch_status, :string, default: "success")
    field(:error_message, :string)
    field(:fetched_at, :utc_datetime)

    belongs_to(:agent, Lincoln.Agents.Agent)
    belongs_to(:topic, Lincoln.Autonomy.ResearchTopic)
    belongs_to(:session, Lincoln.Autonomy.LearningSession)

    timestamps(type: :utc_datetime)
  end

  def changeset(source, attrs) do
    source
    |> cast(attrs, [
      :url,
      :title,
      :domain,
      :content_summary,
      :content_length,
      :facts_extracted,
      :quality_score,
      :fetch_status,
      :error_message,
      :fetched_at,
      :topic_id
    ])
    |> validate_required([:url])
    |> validate_inclusion(:fetch_status, @fetch_statuses)
    |> validate_number(:quality_score, greater_than_or_equal_to: 0, less_than_or_equal_to: 1)
    |> extract_domain()
  end

  def create_changeset(source, attrs, agent_id, session_id) do
    source
    |> changeset(attrs)
    |> put_change(:agent_id, agent_id)
    |> put_change(:session_id, session_id)
    |> put_change(:fetched_at, DateTime.utc_now() |> DateTime.truncate(:second))
  end

  defp extract_domain(changeset) do
    case get_change(changeset, :url) do
      nil ->
        changeset

      url ->
        case URI.parse(url) do
          %{host: host} when is_binary(host) ->
            put_change(changeset, :domain, host)

          _ ->
            changeset
        end
    end
  end

  @doc """
  Assess quality based on domain reputation.
  """
  def domain_quality(domain) when is_binary(domain) do
    cond do
      # Highly trusted sources
      String.contains?(domain, ["wikipedia.org", "docs.python.org", "developer.mozilla.org"]) ->
        1.0

      # Good technical sources
      String.contains?(domain, [".edu", "github.com", "stackoverflow.com"]) ->
        0.85

      # General documentation
      String.contains?(domain, ["docs.", "documentation.", "learn."]) ->
        0.8

      # News and general info
      String.contains?(domain, [".org", ".gov"]) ->
        0.7

      # Default
      true ->
        0.5
    end
  end

  def domain_quality(_), do: 0.5
end
