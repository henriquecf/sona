defmodule SonaWeb.NewConversationLiveTest do
  use SonaWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Sona.CompaniesFixtures

  alias Sona.Companies

  setup :register_and_log_in_team_member

  test "lists active colleagues in your company, not you", %{conn: conn, team_member: me} do
    colleague = team_member_fixture(site: me.site)
    leaver = team_member_fixture(site: me.site)
    {:ok, _} = Companies.offboard_team_member(leaver, DateTime.utc_now(:second))
    stranger = team_member_fixture()

    {:ok, view, _html} = live(conn, ~p"/chats/new")

    assert has_element?(view, "#colleagues-#{colleague.id}")
    refute has_element?(view, "#colleagues-#{me.id}")
    refute has_element?(view, "#colleagues-#{leaver.id}")
    refute has_element?(view, "#colleagues-#{stranger.id}")
  end

  test "picking a colleague opens your conversation with them", %{
    conn: conn,
    scope: scope,
    team_member: me
  } do
    colleague = team_member_fixture(site: me.site)

    {:ok, view, _html} = live(conn, ~p"/chats/new")
    result = view |> element("#colleagues-#{colleague.id} button") |> render_click()

    {:ok, conversation} = Sona.Chat.start_direct_conversation(scope, colleague.id)
    assert {:error, {:live_redirect, %{to: path}}} = result
    assert path == ~p"/chats/#{conversation}"
  end

  test "refuses a colleague id from another company", %{conn: conn} do
    stranger = team_member_fixture()

    {:ok, view, _html} = live(conn, ~p"/chats/new")

    render_click(view, "start", %{"id" => "#{stranger.id}"})

    assert has_element?(view, "#flash-error")
    assert has_element?(view, "#colleagues")
  end
end
