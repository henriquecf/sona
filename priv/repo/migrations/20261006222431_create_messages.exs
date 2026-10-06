defmodule Sona.Repo.Migrations.CreateMessages do
  use Ecto.Migration

  def change do
    create table(:messages) do
      add :body, :text, null: false
      add :conversation_id, references(:conversations, on_delete: :nothing), null: false
      add :author_id, references(:team_members, on_delete: :nothing), null: false

      timestamps(type: :utc_datetime)
    end

    # Messages are read newest-first by id within a conversation (Data Model).
    create index(:messages, [:conversation_id, :id])
    create index(:messages, [:author_id])

    create constraint(:messages, :body_length, check: "char_length(body) BETWEEN 1 AND 4000")
  end
end
