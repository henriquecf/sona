defmodule SonaWeb.ConversationLiveTest do
  use SonaWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Sona.ChatFixtures
  import Sona.CompaniesFixtures

  alias Sona.Chat

  setup :register_and_log_in_team_member

  setup %{team_member: team_member} do
    %{channel: channel_fixture(company: team_member.company, name: "Everyone")}
  end

  test "shows the conversation's messages with their authors", %{
    conn: conn,
    scope: scope,
    channel: channel
  } do
    colleague = team_member_fixture(site: scope.team_member.site, name: "Kwame Mensah")

    message =
      message_fixture(company_scope_fixture(colleague), channel, body: "Fridge 2 is fixed")

    mine = message_fixture(scope, channel, body: "Thanks!")

    {:ok, view, _html} = live(conn, ~p"/chats/#{channel}")

    assert has_element?(view, "#back-bar", "Everyone")
    assert has_element?(view, "#messages-#{message.id}", "Fridge 2 is fixed")
    assert has_element?(view, "#messages-#{message.id} [data-role=author]", "Kwame Mensah")
    assert has_element?(view, "#messages-#{mine.id}[data-mine]")
    refute has_element?(view, "#messages-#{message.id}[data-mine]")
  end

  test "sends a message", %{conn: conn, scope: scope, channel: channel} do
    {:ok, view, _html} = live(conn, ~p"/chats/#{channel}")

    view |> form("#message-form", message: %{body: "Doors in 10"}) |> render_submit()

    assert [message] = Chat.list_messages(scope, channel)
    assert message.body == "Doors in 10"
    assert has_element?(view, "#messages-#{message.id}", "Doors in 10")
  end

  test "doesn't send a blank message", %{conn: conn, scope: scope, channel: channel} do
    {:ok, view, _html} = live(conn, ~p"/chats/#{channel}")

    view |> form("#message-form", message: %{body: "   "}) |> render_submit()

    assert Chat.list_messages(scope, channel) == []
  end

  test "a colleague's open conversation receives the message in real time", %{
    conn: conn,
    scope: scope,
    channel: channel
  } do
    colleague = team_member_fixture(site: scope.team_member.site)
    colleague_conn = log_in_user(build_conn(), Sona.Accounts.get_user!(colleague.user_id))

    {:ok, mine, _html} = live(conn, ~p"/chats/#{channel}")
    {:ok, theirs, _html} = live(colleague_conn, ~p"/chats/#{channel}")

    mine |> form("#message-form", message: %{body: "Busy night, all hands"}) |> render_submit()
    [message] = Chat.list_messages(scope, channel)

    assert has_element?(theirs, "#messages-#{message.id}", "Busy night, all hands")
  end

  test "orders each message by its id, not its arrival", %{
    conn: conn,
    scope: scope,
    channel: channel
  } do
    {:ok, view, _html} = live(conn, ~p"/chats/#{channel}")
    first = message_fixture(scope, channel, body: "first")
    second = message_fixture(scope, channel, body: "second")

    # Broadcasts from different senders can land in either order, so each item
    # carries its id as its CSS order. LiveViewTest can't see visual order; the
    # browser pass checks it.
    assert has_element?(view, ~s|#messages-#{first.id}[style="order: #{first.id}"]|)
    assert has_element?(view, ~s|#messages-#{second.id}[style="order: #{second.id}"]|)
  end

  test "loads older messages on demand, in order", %{conn: conn, scope: scope, channel: channel} do
    [first, second | _] =
      for n <- 1..52, do: message_fixture(scope, channel, body: "Message #{n}")

    {:ok, view, _html} = live(conn, ~p"/chats/#{channel}")

    refute has_element?(view, "#messages-#{first.id}")

    view |> element("#load-older") |> render_click()

    assert has_element?(view, "#messages-#{first.id} + #messages-#{second.id}")
    refute has_element?(view, "#load-older")
  end

  test "refuses a channel outside your audience", %{conn: conn, team_member: team_member} do
    other_site = site_fixture(company: team_member.company)
    channel = channel_fixture(company: team_member.company, site_id: other_site.id)

    assert_raise Ecto.NoResultsError, fn -> live(conn, ~p"/chats/#{channel}") end
  end

  test "refuses another company's channel", %{conn: conn} do
    channel = channel_fixture()

    assert_raise Ecto.NoResultsError, fn -> live(conn, ~p"/chats/#{channel}") end
  end
end
