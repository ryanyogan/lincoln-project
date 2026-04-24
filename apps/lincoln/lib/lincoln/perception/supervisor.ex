defmodule Lincoln.Perception.Supervisor do
  @moduledoc """
  Supervises Lincoln's perception sources.

  Sources are configured under `:lincoln, :perception` as a list of source
  specs. Each spec is `{module, opts}` where `module` implements
  `Lincoln.Perception.Source` and `opts` is a keyword list passed to
  `start_link/1`.

  Example configuration:

      config :lincoln, :perception,
        sources: [
          {Lincoln.Perception.Sources.FileInbox,
           [path: "~/lincoln-inbox", trust_weight: 0.9]}
        ]

  When no sources are configured (default), this supervisor starts with no
  children. That keeps tests and CI quiet, while still placing the supervisor
  in the tree so sources can be added at runtime via `start_source/2`.
  """

  use Supervisor

  def start_link(opts) do
    Supervisor.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl true
  def init(_opts) do
    sources = Application.get_env(:lincoln, :perception, []) |> Keyword.get(:sources, [])

    children =
      sources
      |> Enum.with_index()
      |> Enum.map(fn {{module, source_opts}, idx} ->
        # Give each source a unique id so multiple instances of the same
        # module (e.g. several FileInbox watchers) coexist.
        Supervisor.child_spec({module, source_opts},
          id: {module, idx},
          restart: :permanent
        )
      end)

    Supervisor.init(children, strategy: :one_for_one)
  end

  @doc """
  Start a perception source at runtime.

  Useful for tests and for connecting a source to a freshly-created agent
  without restarting the application.
  """
  def start_source(module, opts) do
    Supervisor.start_child(
      __MODULE__,
      Supervisor.child_spec({module, opts}, id: {module, :erlang.unique_integer([:positive])})
    )
  end
end
