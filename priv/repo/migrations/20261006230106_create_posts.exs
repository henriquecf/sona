defmodule Sona.Repo.Migrations.CreatePosts do
  use Ecto.Migration

  def change do
    create table(:posts) do
      add :kind, :string, null: false
      add :title, :string
      add :body, :text, null: false
      add :department, :string
      add :company_id, references(:companies, on_delete: :nothing), null: false

      add :author_id,
          references(:team_members, with: [company_id: :company_id], on_delete: :nothing),
          null: false

      # Composite with company_id; a NULL site_id (every site) skips the check.
      add :site_id, references(:sites, with: [company_id: :company_id], on_delete: :nothing)

      timestamps(type: :utc_datetime)
    end

    # The feed reads a company's posts newest first, by id.
    create index(:posts, [:company_id, :id])
    create index(:posts, [:author_id])

    create constraint(:posts, :kind_must_be_known, check: "kind IN ('announcement')")

    create constraint(:posts, :department_must_be_known,
             check:
               "department IS NULL OR department IN ('front_of_house', 'kitchen', 'bar', 'reception', 'housekeeping', 'management')"
           )

    create constraint(:posts, :body_length, check: "char_length(body) BETWEEN 1 AND 4000")

    # An announcement has a title of 1 to 120 characters. IS NOT NULL is
    # needed: a CHECK passes when its expression is NULL.
    create constraint(:posts, :post_shape,
             check:
               "kind = 'announcement' AND title IS NOT NULL AND char_length(title) BETWEEN 1 AND 120"
           )
  end
end
