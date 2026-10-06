defmodule Sona.Feed.Acknowledgement do
  @moduledoc """
  The record that a team member read an announcement, and when
  (`inserted_at`). Written once, by `Sona.Feed.acknowledge/2`.
  """
  use Ecto.Schema

  alias Sona.Companies.TeamMember
  alias Sona.Feed.Post

  schema "acknowledgements" do
    belongs_to :post, Post
    belongs_to :team_member, TeamMember

    timestamps(type: :utc_datetime, updated_at: false)
  end
end
