defmodule Sona.Feed.Delivery do
  @moduledoc """
  An announcement sent to one team member, and when they saw and
  acknowledged it (D-008). `Sona.Feed` creates one for each person in the
  announcement's audience as it is posted, and sets each time once.
  """
  use Ecto.Schema

  alias Sona.Companies.{Company, TeamMember}
  alias Sona.Feed.Post

  schema "deliveries" do
    field :seen_at, :utc_datetime
    field :acknowledged_at, :utc_datetime

    belongs_to :company, Company
    belongs_to :post, Post
    belongs_to :team_member, TeamMember
  end
end
