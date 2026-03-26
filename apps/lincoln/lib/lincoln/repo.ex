defmodule Lincoln.Repo do
  use Ecto.Repo,
    otp_app: :lincoln,
    adapter: Ecto.Adapters.Postgres

  # Add pgvector extension for vector type support
  @impl true
  def init(_type, config) do
    {:ok, Keyword.put(config, :types, Lincoln.PostgrexTypes)}
  end
end

# Custom Postgrex types module to support pgvector
Postgrex.Types.define(
  Lincoln.PostgrexTypes,
  [Pgvector.Extensions.Vector] ++ Ecto.Adapters.Postgres.extensions(),
  []
)
