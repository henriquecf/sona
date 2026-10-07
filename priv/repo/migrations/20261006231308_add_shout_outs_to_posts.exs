defmodule Sona.Repo.Migrations.AddShoutOutsToPosts do
  use Ecto.Migration

  @announcement_shape "kind = 'announcement' AND title IS NOT NULL AND char_length(title) BETWEEN 1 AND 120"

  def up do
    alter table(:posts) do
      add :recipient_id,
          references(:team_members, with: [company_id: :company_id], on_delete: :nothing)

      add :company_value_id,
          references(:company_values, with: [company_id: :company_id], on_delete: :nothing)
    end

    create index(:posts, [:recipient_id])

    drop constraint(:posts, :kind_must_be_known)
    drop constraint(:posts, :post_shape)

    create constraint(:posts, :kind_must_be_known, check: "kind IN ('announcement', 'shout_out')")

    # A shout-out names a colleague (never yourself) and a company value, and
    # is for the whole company: no title, site or department.
    create constraint(:posts, :post_shape,
             check: """
             (#{@announcement_shape} AND recipient_id IS NULL AND company_value_id IS NULL)
             OR (kind = 'shout_out' AND title IS NULL AND site_id IS NULL AND department IS NULL
               AND recipient_id IS NOT NULL AND company_value_id IS NOT NULL
               AND recipient_id <> author_id)
             """
           )
  end

  # Rolling back deliberately loses shout-outs: the old constraints can't
  # hold them.
  def down do
    execute("DELETE FROM posts WHERE kind = 'shout_out'")

    drop constraint(:posts, :post_shape)
    drop constraint(:posts, :kind_must_be_known)

    create constraint(:posts, :kind_must_be_known, check: "kind IN ('announcement')")
    create constraint(:posts, :post_shape, check: @announcement_shape)

    drop index(:posts, [:recipient_id])

    alter table(:posts) do
      remove :company_value_id
      remove :recipient_id
    end
  end
end
