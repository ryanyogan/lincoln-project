defmodule Lincoln.Repo.Migrations.AddAttentionParamsToAgents do
  use Ecto.Migration

  def change do
    alter table(:agents) do
      add(:attention_params, :map, default: %{})
    end
  end
end
