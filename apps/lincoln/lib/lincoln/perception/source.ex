defmodule Lincoln.Perception.Source do
  @moduledoc """
  Behaviour for perception sources — file watchers, RSS pollers, API listeners, etc.

  A source is a long-running process (usually a GenServer) that pulls or receives
  external signals and hands `Lincoln.Perception.RawObservation` structs to
  `Lincoln.Perception.ingest/2`. The Perception context handles salience filtering,
  embedding, and persistence.

  Sources are supervised under `Lincoln.Perception.Supervisor`. Each source is
  responsible for its own retries, error handling, and rate limiting — failures
  in one source must not affect others.
  """

  @doc """
  Returns a child_spec for adding the source to a supervision tree.

  Implementations typically delegate to GenServer's auto-generated child_spec
  via `use GenServer` and override `child_spec/1` if needed.
  """
  @callback child_spec(opts :: keyword()) :: Supervisor.child_spec()
end
