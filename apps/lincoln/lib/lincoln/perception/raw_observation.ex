defmodule Lincoln.Perception.RawObservation do
  @moduledoc """
  An external signal entering Lincoln's substrate before salience filtering.

  Sources produce `RawObservation` structs and hand them to `Lincoln.Perception.ingest/2`.
  The salience filter decides whether the observation becomes a memory and at what
  importance.
  """

  @enforce_keys [:source, :content]
  defstruct [
    :source,
    :content,
    :title,
    :url,
    :external_id,
    :occurred_at,
    metadata: %{},
    trust_weight: 0.5
  ]

  @type t :: %__MODULE__{
          source: String.t(),
          content: String.t(),
          title: String.t() | nil,
          url: String.t() | nil,
          external_id: String.t() | nil,
          occurred_at: DateTime.t() | nil,
          metadata: map(),
          trust_weight: float()
        }

  @doc """
  Build a RawObservation, defaulting `occurred_at` to now.
  """
  def new(source, content, opts \\ []) when is_binary(source) and is_binary(content) do
    %__MODULE__{
      source: source,
      content: content,
      title: Keyword.get(opts, :title),
      url: Keyword.get(opts, :url),
      external_id: Keyword.get(opts, :external_id),
      occurred_at: Keyword.get(opts, :occurred_at, DateTime.utc_now()),
      metadata: Keyword.get(opts, :metadata, %{}),
      trust_weight: Keyword.get(opts, :trust_weight, 0.5)
    }
  end
end
