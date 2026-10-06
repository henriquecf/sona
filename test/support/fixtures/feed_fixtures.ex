defmodule Sona.FeedFixtures do
  @moduledoc """
  This module defines test helpers for creating
  entities via the `Sona.Feed` context.
  """

  alias Sona.Feed

  @doc """
  An announcement by `manager_scope`. Pass `site_id:` or `department:` to
  narrow its audience.
  """
  def announcement_fixture(manager_scope, attrs \\ %{}) do
    {:ok, post} =
      Feed.create_announcement(
        manager_scope,
        Enum.into(attrs, %{title: "Rota for next week", body: "It's up in the office."})
      )

    post
  end

  @doc """
  A shout-out from `scope` to `recipient` (a team member) for `value`.
  """
  def shout_out_fixture(scope, recipient, value, attrs \\ %{}) do
    {:ok, post} =
      Feed.create_shout_out(
        scope,
        Enum.into(attrs, %{
          recipient_id: recipient.id,
          company_value_id: value.id,
          body: "Thank you!"
        })
      )

    post
  end
end
