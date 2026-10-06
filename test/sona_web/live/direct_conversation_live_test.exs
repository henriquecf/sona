defmodule SonaWeb.DirectConversationLiveTest do
  use SonaWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Sona.ChatFixtures
  import Sona.CompaniesFixtures

  alias Sona.{Accounts, Chat, Companies}

  setup :register_and_log_in_team_member

  setup %{scope: scope, team_member: me} do
    colleague = team_member_fixture(site: me.site, name: "Kwame Mensah")
    {:ok, conversation} = Chat.start_direct_conversation(scope, colleague.id)
    %{colleague: colleague, conversation: conversation}
  end

  test "is titled with the other person's name", %{conn: conn, conversation: conversation} do
    {:ok, view, _html} = live(conn, ~p"/chats/#{conversation}")

    assert has_element?(view, "#back-bar", "Kwame Mensah")
  end

  test "appears in the other person's chats list with its first message", %{
    conn: conn,
    colleague: colleague,
    conversation: conversation
  } do
    colleague_conn = log_in_user(build_conn(), Accounts.get_user!(colleague.user_id))
    {:ok, their_chats, _html} = live(colleague_conn, ~p"/chats")
    refute has_element?(their_chats, "#conversations-#{conversation.id}")

    {:ok, mine, _html} = live(conn, ~p"/chats/#{conversation}")
    mine |> form("#message-form", message: %{body: "Can you swap Saturday?"}) |> render_submit()

    assert has_element?(
             their_chats,
             "#conversations-#{conversation.id}",
             "Can you swap Saturday?"
           )
  end

  test "a reply after the other person left is refused and explained", %{
    conn: conn,
    scope: scope,
    colleague: colleague,
    conversation: conversation
  } do
    {:ok, view, _html} = live(conn, ~p"/chats/#{conversation}")
    {:ok, _} = Companies.offboard_team_member(colleague, DateTime.utc_now(:second))

    view |> form("#message-form", message: %{body: "Are you still there?"}) |> render_submit()

    assert has_element?(view, "#recipient-left")
    assert Chat.list_messages(scope, conversation) == []
  end

  test "can't be written to once the other person has left", %{
    conn: conn,
    scope: scope,
    colleague: colleague,
    conversation: conversation
  } do
    message_fixture(scope, conversation, body: "Good luck!")
    {:ok, _} = Companies.offboard_team_member(colleague, DateTime.utc_now(:second))

    {:ok, view, _html} = live(conn, ~p"/chats/#{conversation}")

    assert has_element?(view, "#recipient-left")
    refute has_element?(view, "#message-form")
  end
end
