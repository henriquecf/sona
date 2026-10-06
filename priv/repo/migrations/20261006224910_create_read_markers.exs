defmodule Sona.Repo.Migrations.CreateReadMarkers do
  use Ecto.Migration

  def change do
    create table(:read_markers) do
      add :conversation_id, references(:conversations, on_delete: :nothing), null: false
      add :team_member_id, references(:team_members, on_delete: :nothing), null: false
      add :last_read_message_id, references(:messages, on_delete: :nothing), null: false

      timestamps(type: :utc_datetime)
    end

    # One marker per person per conversation, written as an upsert. Owner
    # first, like the other composite indexes; no index on the message id,
    # which no query uses and which would stop the upsert being a HOT update.
    create unique_index(:read_markers, [:team_member_id, :conversation_id])
  end
end
