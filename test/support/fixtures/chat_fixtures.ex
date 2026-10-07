defmodule Sona.ChatFixtures do
  @moduledoc """
  This module defines test helpers for creating
  entities via the `Sona.Chat` context.
  """

  import Sona.CompaniesFixtures

  alias Sona.Chat

  @doc """
  A channel. Pass `company:` to choose its company, and `site_id:` or
  `department:` to narrow its audience.
  """
  def channel_fixture(attrs \\ %{}) do
    {company, attrs} = Map.pop_lazy(Map.new(attrs), :company, &company_fixture/0)

    {:ok, channel} =
      Chat.create_channel(
        company,
        Enum.into(attrs, %{name: "Channel #{System.unique_integer([:positive])}"})
      )

    channel
  end

  def message_fixture(scope, conversation, attrs \\ %{}) do
    {:ok, message} =
      Chat.send_message(scope, conversation, Enum.into(attrs, %{body: "Message"}))

    message
  end
end
