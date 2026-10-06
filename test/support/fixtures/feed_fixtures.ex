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
end
