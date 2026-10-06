defmodule Sona.Repo.Migrations.CreateCompanyValues do
  use Ecto.Migration

  def change do
    create table(:company_values) do
      add :name, :string, null: false
      add :description, :string, null: false
      add :company_id, references(:companies, on_delete: :nothing), null: false

      timestamps(type: :utc_datetime)
    end

    create unique_index(:company_values, [:company_id, :name])

    # Target for composite foreign keys: a shout-out can only cite a value of
    # its own company.
    create unique_index(:company_values, [:id, :company_id])
  end
end
