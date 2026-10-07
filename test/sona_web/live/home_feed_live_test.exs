defmodule SonaWeb.HomeFeedLiveTest do
  use SonaWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Sona.CompaniesFixtures
  import Sona.FeedFixtures

  setup :register_and_log_in_team_member

  setup %{team_member: me} do
    %{manager: company_scope_fixture(team_member_fixture(site: me.site, role: :manager))}
  end

  test "an announcement you haven't acknowledged needs your attention", %{
    conn: conn,
    manager: manager
  } do
    post = announcement_fixture(manager, title: "Rota change")

    {:ok, view, _html} = live(conn, ~p"/")

    assert has_element?(view, "#attention-#{post.id}", "Rota change")
    refute has_element?(view, "#feed-#{post.id}")
  end

  test "acknowledging moves it into the feed", %{conn: conn, manager: manager} do
    post = announcement_fixture(manager)

    {:ok, view, _html} = live(conn, ~p"/")
    view |> element("#acknowledge-#{post.id}") |> render_click()

    refute has_element?(view, "#attention-#{post.id}")
    assert has_element?(view, "#feed-#{post.id} [data-role=acknowledged]")
    # It takes its place by id, newest first, rather than jumping to the top.
    assert has_element?(view, ~s|#feed-#{post.id}[style="order: -#{post.id}"]|)
  end

  @tag :capture_log
  test "a forged acknowledgement for someone else's audience is refused", %{
    conn: conn,
    team_member: me
  } do
    elsewhere = site_fixture(company: me.company)
    other_manager = company_scope_fixture(team_member_fixture(site: elsewhere, role: :manager))
    post = announcement_fixture(other_manager, site_id: elsewhere.id)

    {:ok, view, _html} = live(conn, ~p"/")

    # The id is resolved through the scope, so the view crashes rather than
    # acknowledging (the client reconnects with a fresh view). Trap the exit,
    # since the test process is linked to the view.
    Process.flag(:trap_exit, true)

    assert {{%Ecto.NoResultsError{}, _stack}, _call} =
             catch_exit(render_click(view, "acknowledge", %{"id" => "#{post.id}"}))

    assert Sona.Repo.aggregate(Sona.Feed.Acknowledgement, :count) == 0
  end

  test "a new announcement for your audience arrives live", %{conn: conn, manager: manager} do
    {:ok, view, _html} = live(conn, ~p"/")

    post = announcement_fixture(manager, title: "Doors at 5:30")

    assert has_element?(view, "#attention-#{post.id}", "Doors at 5:30")
  end

  test "a manager's own announcement arrives in their feed, not their attention", %{
    manager: manager
  } do
    {:ok, view, _html} = live(log_in_user(build_conn(), manager.user), ~p"/")

    post = announcement_fixture(manager, title: "My own news")

    assert has_element?(view, "#feed-#{post.id}", "My own news")
    refute has_element?(view, "#attention-#{post.id}")
  end

  test "loads older posts on demand", %{conn: conn, scope: scope, manager: manager} do
    posts = for n <- 1..21, do: announcement_fixture(manager, title: "Post #{n}")
    for post <- posts, do: Sona.Feed.acknowledge(scope, post.id)
    [oldest | _] = posts

    {:ok, view, _html} = live(conn, ~p"/")
    refute has_element?(view, "#feed-#{oldest.id}")

    view |> element("#load-more") |> render_click()

    assert has_element?(view, "#feed-#{oldest.id}")
    refute has_element?(view, "#load-more")
  end

  test "only managers get the announcement button", %{conn: conn, manager: manager} do
    {:ok, view, _html} = live(conn, ~p"/")
    refute has_element?(view, "#new-announcement")
    assert has_element?(view, ~s|#new-shout-out[href="/shout-outs/new"]|)

    manager_conn = log_in_user(build_conn(), manager.user)
    {:ok, manager_view, _html} = live(manager_conn, ~p"/")
    assert has_element?(manager_view, ~s|#new-announcement[href="/announcements/new"]|)
  end
end
