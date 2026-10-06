defmodule SonaWeb.NewAnnouncementLiveTest do
  use SonaWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Sona.CompaniesFixtures

  alias Sona.Feed

  describe "a manager" do
    setup %{conn: conn} do
      manager = team_member_fixture(role: :manager)
      scope = company_scope_fixture(manager)
      %{conn: log_in_user(conn, scope.user), scope: scope}
    end

    test "posts an announcement to an audience and goes home", %{conn: conn, scope: scope} do
      site = scope.team_member.site

      {:ok, view, _html} = live(conn, ~p"/announcements/new")

      assert {:error, {:live_redirect, %{to: "/"}}} =
               view
               |> form("#announcement-form",
                 post: %{
                   title: "Fridge 2",
                   body: "Engineer at 3pm",
                   site_id: site.id,
                   department: "kitchen"
                 }
               )
               |> render_submit()

      assert [post] = Feed.list_feed(scope)
      assert {post.title, post.site_id, post.department} == {"Fridge 2", site.id, :kitchen}
    end

    test "only offers their own company's sites", %{conn: conn, scope: scope} do
      other_site = site_fixture()

      {:ok, view, _html} = live(conn, ~p"/announcements/new")

      assert has_element?(view, ~s|#post_site_id option[value="#{scope.team_member.site_id}"]|)
      refute has_element?(view, ~s|#post_site_id option[value="#{other_site.id}"]|)
    end

    test "shows what's missing", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/announcements/new")

      view |> form("#announcement-form", post: %{title: "", body: ""}) |> render_submit()

      assert has_element?(view, "#announcement-form", "can't be blank")
    end
  end

  test "staff are sent home", %{conn: conn} do
    %{conn: conn} = register_and_log_in_team_member(%{conn: conn})

    assert {:error, {:live_redirect, %{to: "/"}}} = live(conn, ~p"/announcements/new")
  end
end
