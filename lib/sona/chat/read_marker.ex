defmodule Sona.Chat.ReadMarker do
  @moduledoc """
  How far a team member has read a conversation: the last message they've
  seen. Created on first read and only ever moved forward, so a late or
  repeated read can't make messages unread again (docs/architecture.md,
  Data Model).
  """
  use Ecto.Schema

  alias Sona.Chat.{Conversation, Message}
  alias Sona.Companies.TeamMember

  schema "read_markers" do
    belongs_to :conversation, Conversation
    belongs_to :team_member, TeamMember
    belongs_to :last_read_message, Message

    timestamps(type: :utc_datetime)
  end
end
