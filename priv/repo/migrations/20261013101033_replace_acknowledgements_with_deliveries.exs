defmodule Sona.Repo.Migrations.ReplaceAcknowledgementsWithDeliveries do
  use Ecto.Migration

  # D-008: an announcement records who it was sent to, and when each person
  # saw and acknowledged it. Acknowledgements become a column.
  def up do
    create unique_index(:posts, [:id, :company_id])

    create table(:deliveries) do
      add :company_id, references(:companies, on_delete: :nothing), null: false

      add :post_id,
          references(:posts, with: [company_id: :company_id], on_delete: :nothing),
          null: false

      add :team_member_id,
          references(:team_members, with: [company_id: :company_id], on_delete: :nothing),
          null: false

      add :seen_at, :utc_datetime
      add :acknowledged_at, :utc_datetime
    end

    # One per person per announcement, owner first: "Needs your attention".
    create unique_index(:deliveries, [:team_member_id, :post_id])
    # An announcement's stats.
    create index(:deliveries, [:post_id])

    # IS NULL is needed on both sides: a CHECK passes when its expression is NULL.
    create constraint(:deliveries, :acknowledged_means_seen,
             check: "acknowledged_at IS NULL OR seen_at IS NOT NULL"
           )

    # Earlier announcements went to the audience members (by today's site and
    # department: transfers aren't recorded) who had joined and not yet left
    # when it was posted, as "Needs your attention" worked out, plus anyone
    # who acknowledged it. When the rest saw it is unknown.
    execute("""
    INSERT INTO deliveries (company_id, post_id, team_member_id, seen_at, acknowledged_at)
    SELECT p.company_id, p.id, tm.id, a.inserted_at, a.inserted_at
    FROM posts p
    JOIN team_members tm ON tm.company_id = p.company_id AND tm.id <> p.author_id
    LEFT JOIN acknowledgements a ON a.post_id = p.id AND a.team_member_id = tm.id
    WHERE p.kind = 'announcement'
      AND (
        a.id IS NOT NULL
        OR ((p.site_id IS NULL OR p.site_id = tm.site_id)
          AND (p.department IS NULL OR p.department = tm.department)
          AND tm.inserted_at <= p.inserted_at
          AND (tm.left_at IS NULL OR tm.left_at > p.inserted_at))
      )
    """)

    drop table(:acknowledgements)
  end

  def down do
    create table(:acknowledgements) do
      add :post_id, references(:posts, on_delete: :nothing), null: false
      add :team_member_id, references(:team_members, on_delete: :nothing), null: false

      timestamps(type: :utc_datetime, updated_at: false)
    end

    create unique_index(:acknowledgements, [:team_member_id, :post_id])

    execute("""
    INSERT INTO acknowledgements (post_id, team_member_id, inserted_at)
    SELECT post_id, team_member_id, acknowledged_at
    FROM deliveries
    WHERE acknowledged_at IS NOT NULL
    """)

    drop table(:deliveries)
    drop index(:posts, [:id, :company_id])
  end
end
