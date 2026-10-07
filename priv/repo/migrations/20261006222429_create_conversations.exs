defmodule Sona.Repo.Migrations.CreateConversations do
  use Ecto.Migration

  def change do
    # Target for composite foreign keys, so rows that point at a team member
    # can only point at one in their own company.
    create unique_index(:team_members, [:id, :company_id])

    create table(:conversations) do
      add :kind, :string, null: false
      add :name, :string
      add :department, :string
      add :company_id, references(:companies, on_delete: :nothing), null: false

      # Composite with company_id; a NULL site_id (every site) skips the check.
      add :site_id, references(:sites, with: [company_id: :company_id], on_delete: :nothing)

      add :team_member_a_id,
          references(:team_members, with: [company_id: :company_id], on_delete: :nothing)

      add :team_member_b_id,
          references(:team_members, with: [company_id: :company_id], on_delete: :nothing)

      timestamps(type: :utc_datetime)
    end

    create index(:conversations, [:company_id])
    create index(:conversations, [:team_member_b_id])

    create unique_index(:conversations, [:company_id, :name],
             where: "kind = 'channel'",
             name: :conversations_channel_name_index
           )

    create unique_index(:conversations, [:team_member_a_id, :team_member_b_id],
             where: "kind = 'direct'",
             name: :conversations_direct_pair_index
           )

    create constraint(:conversations, :kind_must_be_known, check: "kind IN ('channel', 'direct')")

    create constraint(:conversations, :department_must_be_known,
             check:
               "department IS NULL OR department IN ('front_of_house', 'kitchen', 'bar', 'reception', 'housekeeping', 'management')"
           )

    # A channel has a name and an audience; a direct conversation has exactly
    # two different team members, stored in id order, and nothing else.
    create constraint(:conversations, :conversation_shape,
             check: """
             (kind = 'channel' AND name IS NOT NULL
               AND team_member_a_id IS NULL AND team_member_b_id IS NULL)
             OR (kind = 'direct' AND name IS NULL AND site_id IS NULL AND department IS NULL
               AND team_member_a_id IS NOT NULL AND team_member_b_id IS NOT NULL
               AND team_member_a_id < team_member_b_id)
             """
           )
  end
end
