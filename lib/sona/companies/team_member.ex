defmodule Sona.Companies.TeamMember do
  use Ecto.Schema
  import Ecto.Changeset

  alias Sona.Accounts.User
  alias Sona.Companies.{Company, Site}

  schema "team_members" do
    field :name, :string

    field :department, Ecto.Enum,
      values: [:front_of_house, :kitchen, :bar, :reception, :housekeeping, :management]

    field :role, Ecto.Enum, values: [:staff, :manager]
    field :left_at, :utc_datetime

    belongs_to :company, Company
    belongs_to :site, Site
    belongs_to :user, User

    timestamps(type: :utc_datetime)
  end

  @doc """
  A changeset for the fields a person's details can set. The company, site
  and user are set by `Sona.Companies`, never cast.
  """
  def changeset(team_member, attrs) do
    team_member
    |> cast(attrs, [:name, :department, :role])
    |> validate_required([:name, :department, :role])
    |> check_constraint(:department, name: :department_must_be_known)
    |> check_constraint(:role, name: :role_must_be_known)
    |> foreign_key_constraint(:company_id)
    |> foreign_key_constraint(:site_id)
    |> foreign_key_constraint(:user_id)
    |> unique_constraint(:user_id,
      name: :team_members_active_user_id_index,
      message: "already belongs to a team"
    )
  end
end
