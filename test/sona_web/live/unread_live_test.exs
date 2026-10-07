defmodule SonaWeb.UnreadLiveTest do
  use SonaWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Sona.ChatFixtures
  import Sona.CompaniesFixtures

  setup :register_and_log_in_team_member

  setup %{team_member: me} do
    %{
      channel: channel_fixture(company: me.company),
      colleague: company_scope_fixture(team_member_fixture(site: me.site))
    }
  end

  test "the chats list shows how many messages you haven't read", %{
    conn: conn,
    channel: channel,
    colleague: colleague
  } do
    message_fixture(colleague, channel)
    message_fixture(colleague, channel)

    {:ok, view, _html} = live(conn, ~p"/chats")

    assert has_element?(view, "#conversations-#{channel.id} [data-role=unread]", "2")
  end

  test "opening a conversation marks it read", %{
    conn: conn,
    channel: channel,
    colleague: colleague
  } do
    message_fixture(colleague, channel)
    message_fixture(colleague, channel)

    {:ok, _conversation, _html} = live(conn, ~p"/chats/#{channel}")
    {:ok, chats, _html} = live(conn, ~p"/chats")

    refute has_element?(chats, "#conversations-#{channel.id} [data-role=unread]")
  end

  test "the first, static render of a conversation doesn't read it", %{
    conn: conn,
    channel: channel,
    colleague: colleague
  } do
    message_fixture(colleague, channel)

    conn |> get(~p"/chats/#{channel}") |> html_response(200)
    {:ok, chats, _html} = live(conn, ~p"/chats")

    assert has_element?(chats, "#conversations-#{channel.id} [data-role=unread]", "1")
  end

  test "the count rises live as colleagues write", %{
    conn: conn,
    channel: channel,
    colleague: colleague
  } do
    {:ok, view, _html} = live(conn, ~p"/chats")
    refute has_element?(view, "#conversations-#{channel.id} [data-role=unread]")

    message_fixture(colleague, channel)

    assert has_element?(view, "#conversations-#{channel.id} [data-role=unread]", "1")
  end

  test "messages arriving while the conversation is open are read", %{
    conn: conn,
    channel: channel,
    colleague: colleague
  } do
    {:ok, conversation, _html} = live(conn, ~p"/chats/#{channel}")
    message = message_fixture(colleague, channel)
    assert has_element?(conversation, "#messages-#{message.id}")

    {:ok, chats, _html} = live(conn, ~p"/chats")

    refute has_element?(chats, "#conversations-#{channel.id} [data-role=unread]")
  end
end
