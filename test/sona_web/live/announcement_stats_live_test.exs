defmodule SonaWeb.AnnouncementStatsLiveTest do
  use SonaWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Sona.CompaniesFixtures
  import Sona.FeedFixtures

  alias Sona.{Companies, Feed}

  # I'm staff at a site. The author manages it; the manager works at
  # another site, so announcements to mine aren't sent to them.
  setup :register_and_log_in_team_member

  setup %{team_member: me} do
    elsewhere = site_fixture(company: me.company)
    manager = company_scope_fixture(team_member_fixture(site: elsewhere, role: :manager))

    %{
      author: company_scope_fixture(team_member_fixture(site: me.site, role: :manager)),
      manager: manager,
      manager_conn: log_in_user(build_conn(), manager.user)
    }
  end

  describe "access" do
    test "staff are sent back to Home", %{conn: conn, author: author} do
      post = announcement_fixture(author)

      assert {:error, {:redirect, %{to: "/"}}} = live(conn, ~p"/announcements/stats")
      assert {:error, {:redirect, %{to: "/"}}} = live(conn, ~p"/announcements/#{post.id}/stats")
    end

    test "managers get a Stats link on Home", %{conn: conn, manager_conn: manager_conn} do
      {:ok, view, _html} = live(conn, ~p"/")
      refute has_element?(view, "#announcement-stats")

      {:ok, manager_view, _html} = live(manager_conn, ~p"/")
      assert has_element?(manager_view, ~s|#announcement-stats[href="/announcements/stats"]|)
    end

    @tag :capture_log
    test "another company's announcement isn't found", %{manager_conn: manager_conn} do
      other_manager = company_scope_fixture(team_member_fixture(role: :manager))
      elsewhere = announcement_fixture(other_manager)

      assert_raise Ecto.NoResultsError, fn ->
        live(manager_conn, ~p"/announcements/#{elsewhere.id}/stats")
      end
    end
  end

  describe "the list" do
    test "shows every announcement with its counts, linking to who", %{
      manager_conn: manager_conn,
      author: author,
      scope: scope,
      team_member: me
    } do
      post = announcement_fixture(author, site_id: me.site_id)
      {:ok, _} = Feed.acknowledge(scope, post.id)

      {:ok, view, _html} = live(manager_conn, ~p"/announcements/stats")

      assert has_count?(view, post, sent: 1, seen: 1, acknowledged: 1, left: 0)

      assert has_element?(
               view,
               ~s|#announcements-#{post.id} a[href="/announcements/#{post.id}/stats"]|
             )
    end

    test "loads older announcements on demand", %{manager_conn: manager_conn, author: author} do
      [oldest | _] = for _ <- 1..21, do: announcement_fixture(author)

      {:ok, view, _html} = live(manager_conn, ~p"/announcements/stats")
      refute has_element?(view, "#announcements-#{oldest.id}")

      view |> element("#load-more") |> render_click()

      assert has_element?(view, "#announcements-#{oldest.id}")
      refute has_element?(view, "#load-more")
    end

    test "loading more after the last page changes nothing", %{
      manager_conn: manager_conn,
      author: author,
      scope: scope
    } do
      [oldest | _] = for _ <- 1..21, do: announcement_fixture(author)
      {:ok, view, _html} = live(manager_conn, ~p"/announcements/stats")

      view |> element("#load-more") |> render_click()
      # A second tap that was already on its way.
      render_click(view, "load-more", %{})
      {:ok, _} = Feed.acknowledge(scope, oldest.id)

      refute has_element?(view, "#load-more")
      assert has_count?(view, oldest, acknowledged: 1)
    end

    test "updates live as staff see and acknowledge an announcement", %{
      conn: conn,
      manager_conn: manager_conn,
      author: author,
      team_member: me
    } do
      post = announcement_fixture(author, site_id: me.site_id)
      {:ok, view, _html} = live(manager_conn, ~p"/announcements/stats")

      {:ok, home, _html} = live(conn, ~p"/")
      assert has_count?(view, post, seen: 1, acknowledged: 0)

      home |> element("#acknowledge-#{post.id}") |> render_click()
      assert has_count?(view, post, seen: 1, acknowledged: 1)
    end

    test "shows the first announcement as it is posted", %{
      manager_conn: manager_conn,
      author: author
    } do
      {:ok, view, _html} = live(manager_conn, ~p"/announcements/stats")

      post = announcement_fixture(author)

      assert has_element?(view, "#announcements-#{post.id}")
    end

    test "updates live, adding new announcements and leaving older ones unloaded", %{
      manager_conn: manager_conn,
      author: author,
      scope: scope
    } do
      [oldest | posts] = for _ <- 1..21, do: announcement_fixture(author)
      loaded = List.last(posts)
      {:ok, view, _html} = live(manager_conn, ~p"/announcements/stats")

      {:ok, _} = Feed.acknowledge(scope, loaded.id)
      {:ok, _} = Feed.acknowledge(scope, oldest.id)
      new = announcement_fixture(author)

      assert has_count?(view, loaded, acknowledged: 1)
      assert has_element?(view, "#announcements-#{new.id}")
      refute has_element?(view, "#announcements-#{oldest.id}")
    end
  end

  describe "one announcement" do
    test "shows who is in each group", %{
      manager_conn: manager_conn,
      author: author,
      scope: scope,
      team_member: me
    } do
      [not_seen, seen, left] = for _ <- 1..3, do: team_member_fixture(site: me.site)
      post = announcement_fixture(author, site_id: me.site_id)
      {:ok, _} = Feed.acknowledge(scope, post.id)
      :ok = Feed.mark_seen(company_scope_fixture(seen), [post])
      {:ok, _} = Companies.offboard_team_member(left, DateTime.utc_now(:second))

      {:ok, view, _html} = live(manager_conn, ~p"/announcements/#{post.id}/stats")

      assert has_count?(view, post, sent: 4, seen: 2, acknowledged: 1, left: 1)
      assert has_element?(view, "#not-seen #team-member-#{not_seen.id}")
      assert has_element?(view, "#seen #team-member-#{seen.id}")
      assert has_element?(view, "#acknowledged #team-member-#{me.id}")
      assert has_element?(view, "#left #team-member-#{left.id}")
    end

    test "updates live as staff see and acknowledge it", %{
      conn: conn,
      manager_conn: manager_conn,
      author: author,
      team_member: me
    } do
      post = announcement_fixture(author, site_id: me.site_id)
      {:ok, stats_view, _html} = live(manager_conn, ~p"/announcements/#{post.id}/stats")
      assert has_element?(stats_view, "#not-seen #team-member-#{me.id}")

      {:ok, home, _html} = live(conn, ~p"/")
      assert has_element?(stats_view, "#seen #team-member-#{me.id}")

      home |> element("#acknowledge-#{post.id}") |> render_click()
      assert has_element?(stats_view, "#acknowledged #team-member-#{me.id}")
      assert has_count?(stats_view, post, seen: 1, acknowledged: 1)
    end

    test "ignores other announcements' changes", %{
      manager_conn: manager_conn,
      author: author,
      scope: scope,
      team_member: me
    } do
      post = announcement_fixture(author, site_id: me.site_id)
      other = announcement_fixture(author, site_id: me.site_id)
      {:ok, stats_view, _html} = live(manager_conn, ~p"/announcements/#{post.id}/stats")

      {:ok, _} = Feed.acknowledge(scope, other.id)

      assert has_element?(stats_view, "#not-seen #team-member-#{me.id}")
    end
  end

  defp has_count?(view, post, counts) do
    Enum.all?(counts, fn {stat, count} ->
      has_element?(view, ~s|#stats-#{post.id} [data-stat="#{stat}"][data-count="#{count}"]|)
    end)
  end
end
