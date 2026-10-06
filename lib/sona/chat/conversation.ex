defmodule Sona.Chat.Conversation do
  use Ecto.Schema
  import Ecto.Changeset

  alias Sona.Companies.{Company, Site, TeamMember}

  schema "conversations" do
    field :kind, Ecto.Enum, values: [:channel, :direct]
    field :name, :string
    field :department, Ecto.Enum, values: Ecto.Enum.values(TeamMember, :department)

    belongs_to :company, Company
    belongs_to :site, Site
    belongs_to :team_member_a, TeamMember
    belongs_to :team_member_b, TeamMember

    timestamps(type: :utc_datetime)
  end

  @doc """
  A changeset for a channel: a name and an audience (`site_id` and
  `department`, where `nil` means every site or every department, D-004).
  """
  def channel_changeset(conversation, attrs) do
    conversation
    |> cast(attrs, [:name, :site_id, :department])
    |> validate_required([:name])
    |> put_change(:kind, :channel)
    |> foreign_key_constraint(:company_id)
    |> foreign_key_constraint(:site_id)
    |> unique_constraint(:name, name: :conversations_channel_name_index)
    |> check_constraint(:kind, name: :kind_must_be_known)
    |> check_constraint(:department, name: :department_must_be_known)
    |> check_constraint(:name, name: :conversation_shape)
  end
end
