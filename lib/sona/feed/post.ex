defmodule Sona.Feed.Post do
  use Ecto.Schema
  import Ecto.Changeset

  alias Sona.Companies.{Company, CompanyValue, Site, TeamMember}

  schema "posts" do
    field :kind, Ecto.Enum, values: [:announcement, :shout_out]
    field :title, :string
    field :body, :string
    field :department, Ecto.Enum, values: Ecto.Enum.values(TeamMember, :department)

    belongs_to :company, Company
    belongs_to :author, TeamMember
    belongs_to :site, Site
    belongs_to :recipient, TeamMember
    belongs_to :company_value, CompanyValue

    # When the scope's team member acknowledged it, set by `Sona.Feed`.
    field :acknowledged_at, :utc_datetime, virtual: true

    timestamps(type: :utc_datetime)
  end

  @doc """
  A changeset for an announcement: a title, a body and an audience
  (`site_id` and `department`, where `nil` means every, D-004). The
  company and author are set by `Sona.Feed` from the scope, never cast.
  """
  def announcement_changeset(post, attrs) do
    post
    |> cast(attrs, [:title, :body, :site_id, :department])
    |> validate_required([:title, :body])
    # Code points, to match the database's char_length.
    |> validate_length(:title, max: 120, count: :codepoints)
    |> validate_length(:body, max: 4000, count: :codepoints)
    |> put_change(:kind, :announcement)
    |> foreign_key_constraint(:company_id)
    |> foreign_key_constraint(:author_id)
    |> foreign_key_constraint(:site_id)
    |> check_constraint(:kind, name: :kind_must_be_known)
    |> check_constraint(:department, name: :department_must_be_known)
    |> check_constraint(:body, name: :body_length)
    |> check_constraint(:title, name: :post_shape)
  end

  @doc """
  A changeset for a shout-out: a colleague, a company value and a message.
  It is for the whole company, so it has no title, site or department. The
  company and author are set by `Sona.Feed` from the scope, never cast.
  """
  def shout_out_changeset(post, attrs) do
    post
    |> cast(attrs, [:body, :recipient_id, :company_value_id])
    |> validate_required([:recipient_id, :company_value_id, :body])
    |> validate_length(:body, max: 4000, count: :codepoints)
    |> put_change(:kind, :shout_out)
    |> foreign_key_constraint(:company_id)
    |> foreign_key_constraint(:author_id)
    |> foreign_key_constraint(:recipient_id)
    |> foreign_key_constraint(:company_value_id)
    |> check_constraint(:kind, name: :kind_must_be_known)
    |> check_constraint(:body, name: :body_length)
    |> check_constraint(:recipient_id, name: :post_shape)
  end
end
