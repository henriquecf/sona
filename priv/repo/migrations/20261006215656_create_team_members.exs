defmodule Sona.Repo.Migrations.CreateTeamMembers do
  use Ecto.Migration

  def change do
    create table(:team_members) do
      add :name, :string, null: false
      add :department, :string, null: false
      add :role, :string, null: false
      add :left_at, :utc_datetime
      add :company_id, references(:companies, on_delete: :nothing), null: false

      add :site_id,
          references(:sites, with: [company_id: :company_id], on_delete: :nothing),
          null: false

      add :user_id, references(:users, on_delete: :nothing), null: false

      timestamps(type: :utc_datetime)
    end

    create index(:team_members, [:company_id])
    create index(:team_members, [:site_id])
    create index(:team_members, [:user_id])

    create unique_index(:team_members, [:user_id],
             where: "left_at IS NULL",
             name: :team_members_active_user_id_index
           )

    create constraint(:team_members, :department_must_be_known,
             check:
               "department IN ('front_of_house', 'kitchen', 'bar', 'reception', 'housekeeping', 'management')"
           )

    create constraint(:team_members, :role_must_be_known, check: "role IN ('staff', 'manager')")
  end
end
