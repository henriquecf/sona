defmodule Sona.Chat.UnreadTest do
  use Sona.DataCase, async: true

  import Sona.ChatFixtures
  import Sona.CompaniesFixtures

  alias Sona.Chat
  alias Sona.Companies.TeamMember

  setup do
    company = company_fixture()
    site = site_fixture(company: company)
    channel = channel_fixture(company: company)

    %{
      channel: channel,
      me: company_scope_fixture(team_member_fixture(site: site)),
      colleague: company_scope_fixture(team_member_fixture(site: site))
    }
  end

  test "counts colleagues' messages since you last read", %{
    channel: channel,
    me: me,
    colleague: colleague
  } do
    read = message_fixture(colleague, channel)
    :ok = Chat.mark_read(me, read)
    message_fixture(colleague, channel)
    message_fixture(colleague, channel)

    assert unread(me, channel) == 2
  end

  test "a colleague reading doesn't read it for you", %{
    channel: channel,
    me: me,
    colleague: colleague
  } do
    message = message_fixture(colleague, channel)
    :ok = Chat.mark_read(colleague, message)

    assert unread(me, channel) == 1
  end

  test "reading one conversation doesn't read another", %{
    channel: channel,
    me: me,
    colleague: colleague
  } do
    other = channel_fixture(company: me.team_member.company)
    message_fixture(colleague, other)
    :ok = Chat.mark_read(me, message_fixture(colleague, channel))

    assert unread(me, other) == 1
  end

  test "can't mark a message read in colleagues' direct conversation", %{
    me: me,
    colleague: colleague
  } do
    third = team_member_fixture(site: colleague.team_member.site)
    {:ok, direct} = Chat.start_direct_conversation(colleague, third.id)
    message = message_fixture(colleague, direct)

    assert_raise Ecto.NoResultsError, fn -> Chat.mark_read(me, message) end
  end

  test "never counts your own messages", %{channel: channel, me: me} do
    message_fixture(me, channel)

    assert unread(me, channel) == 0
  end

  test "reading only moves forward", %{channel: channel, me: me, colleague: colleague} do
    older = message_fixture(colleague, channel)
    newer = message_fixture(colleague, channel)

    :ok = Chat.mark_read(me, newer)
    :ok = Chat.mark_read(me, older)

    assert unread(me, channel) == 0
  end

  test "messages from before you joined don't count", %{channel: channel, colleague: colleague} do
    message_fixture(colleague, channel)
    newcomer = team_member_fixture(site: colleague.team_member.site)

    # Joined a minute after that message.
    Repo.update_all(from(t in TeamMember, where: t.id == ^newcomer.id),
      set: [inserted_at: DateTime.add(DateTime.utc_now(:second), 60)]
    )

    assert unread(company_scope_fixture(newcomer), channel) == 0
  end

  test "can't mark a message read in a conversation you can't see", %{me: me} do
    stranger = company_scope_fixture()
    message = message_fixture(stranger, channel_fixture(company: stranger.team_member.company))

    assert_raise Ecto.NoResultsError, fn -> Chat.mark_read(me, message) end
  end

  defp unread(scope, conversation) do
    scope
    |> Chat.list_conversations()
    |> Enum.find(&(&1.id == conversation.id))
    |> Map.fetch!(:unread_count)
  end
end
