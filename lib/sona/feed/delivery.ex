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

  @doc """
  Where the person it was sent to stands, as the stats group them:
  `:acknowledged`, `:left` (without acknowledging), `:seen` (but not
  acknowledged) or `:not_seen`. Needs the team member loaded.
  """
  def status(%__MODULE__{acknowledged_at: %DateTime{}}), do: :acknowledged
  def status(%__MODULE__{team_member: %TeamMember{left_at: %DateTime{}}}), do: :left
  def status(%__MODULE__{team_member: %TeamMember{}, seen_at: %DateTime{}}), do: :seen
  def status(%__MODULE__{team_member: %TeamMember{}, seen_at: nil}), do: :not_seen
end
