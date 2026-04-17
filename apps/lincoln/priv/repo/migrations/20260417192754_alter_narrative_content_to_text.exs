defmodule Lincoln.Repo.Migrations.AlterNarrativeContentToText do
  use Ecto.Migration

  def change do
    alter table(:narrative_reflections) do
      modify :content, :text, from: :string
    end
  end
end
