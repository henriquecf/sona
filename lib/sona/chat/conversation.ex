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

    # Set by `Sona.Chat.list_conversations/1` for the scope's team member.
    field :last_message, :any, virtual: true
    field :unread_count, :integer, virtual: true, default: 0

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

  @doc """
  A changeset for a direct conversation between two team members, stored
  in id order (`team_member_a_id < team_member_b_id`, D-004).
  """
  def direct_changeset(conversation, team_member_a_id, team_member_b_id) do
    conversation
    |> change(
      kind: :direct,
      team_member_a_id: team_member_a_id,
      team_member_b_id: team_member_b_id
    )
    |> foreign_key_constraint(:company_id)
    |> foreign_key_constraint(:team_member_a_id)
    |> foreign_key_constraint(:team_member_b_id)
    |> unique_constraint([:team_member_a_id, :team_member_b_id],
      name: :conversations_direct_pair_index
    )
    |> check_constraint(:team_member_b_id, name: :conversation_shape)
  end
end
