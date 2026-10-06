defmodule Sona.Repo.Migrations.CreateAcknowledgements do
  use Ecto.Migration

  def change do
    # Who read an announcement, and when: a record, not a boolean.
    create table(:acknowledgements) do
      add :post_id, references(:posts, on_delete: :nothing), null: false
      add :team_member_id, references(:team_members, on_delete: :nothing), null: false

      timestamps(type: :utc_datetime, updated_at: false)
    end

    # One per person per announcement, owner first.
    create unique_index(:acknowledgements, [:team_member_id, :post_id])
  end
end
