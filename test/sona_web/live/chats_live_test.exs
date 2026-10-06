defmodule SonaWeb.ChatsLiveTest do
  use SonaWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Sona.ChatFixtures
  import Sona.CompaniesFixtures

  setup :register_and_log_in_team_member

  test "lists the channels in your audience, each linking to its conversation", %{
    conn: conn,
    team_member: team_member
  } do
    everyone = channel_fixture(company: team_member.company, name: "Everyone")
    my_site = channel_fixture(company: team_member.company, site_id: team_member.site_id)
    other_site = site_fixture(company: team_member.company)
    elsewhere = channel_fixture(company: team_member.company, site_id: other_site.id)
    other_company = channel_fixture()

    {:ok, view, _html} = live(conn, ~p"/chats")

    assert has_element?(view, ~s|#conversations-#{everyone.id} a[href="/chats/#{everyone.id}"]|)
    assert has_element?(view, "#conversations-#{my_site.id}")
    refute has_element?(view, "#conversations-#{elsewhere.id}")
    refute has_element?(view, "#conversations-#{other_company.id}")
  end

  test "a colleague's channel message moves that channel to the top, with a preview", %{
    conn: conn,
    team_member: team_member
  } do
    quiet = channel_fixture(company: team_member.company, name: "A quiet channel")
    busy = channel_fixture(company: team_member.company, name: "Busy")

    colleague =
      company_scope_fixture(team_member_fixture(site: team_member.site, name: "Kwame Mensah"))

    {:ok, view, _html} = live(conn, ~p"/chats")
    message_fixture(colleague, busy, body: "Doors in 10")

    assert has_element?(view, "#conversations-#{busy.id}", "Kwame: Doors in 10")
    assert conversation_ids(view) == ["conversations-#{busy.id}", "conversations-#{quiet.id}"]
  end

  test "your own last message is previewed as yours", %{
    conn: conn,
    scope: scope,
    team_member: team_member
  } do
    channel = channel_fixture(company: team_member.company)
    message_fixture(scope, channel, body: "On my way")

    {:ok, view, _html} = live(conn, ~p"/chats")

    assert has_element?(view, "#conversations-#{channel.id}", "You: On my way")
  end

  defp conversation_ids(view) do
    view
    |> render()
    |> LazyHTML.from_fragment()
    |> LazyHTML.query("#conversations > li:not(#conversations-empty)")
    |> LazyHTML.attribute("id")
  end

  test "lists nothing but the empty state when there are no conversations", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/chats")

    assert has_element?(view, "#conversations-empty")
    refute has_element?(view, "#conversations > li:not(#conversations-empty)")
  end
end
