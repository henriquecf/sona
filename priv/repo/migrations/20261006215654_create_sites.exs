defmodule Sona.Repo.Migrations.CreateSites do
  use Ecto.Migration

  def change do
    create table(:sites) do
      add :name, :string, null: false
      add :company_id, references(:companies, on_delete: :nothing), null: false

      timestamps(type: :utc_datetime)
    end

    create unique_index(:sites, [:company_id, :name])

    # Target for composite foreign keys, so rows that point at a site
    # can only point at one in their own company.
    create unique_index(:sites, [:id, :company_id])
  end
end
