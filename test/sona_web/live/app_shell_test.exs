defmodule SonaWeb.AppShellTest do
  use SonaWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Sona.AccountsFixtures

  describe "for a team member" do
    setup :register_and_log_in_team_member

    test "home has the header and the tab bar, with Home current", %{conn: conn, team_member: tm} do
      {:ok, view, _html} = live(conn, ~p"/")

      assert has_element?(view, "#app-header", tm.site.name)
      assert has_element?(view, "#app-header", tm.company.name)
      assert has_element?(view, "#tab-home[aria-current=page]")
      assert has_element?(view, ~s|#tab-chats[href="/chats"]|)
      refute has_element?(view, "#tab-chats[aria-current=page]")
    end

    test "the chats tab is current on /chats", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/chats")

      assert has_element?(view, "#tab-chats[aria-current=page]")
      refute has_element?(view, "#tab-home[aria-current=page]")
    end

    test "the account menu shows who you are and lets you log out", %{conn: conn, team_member: tm} do
      {:ok, view, _html} = live(conn, ~p"/")

      assert has_element?(view, "#account-menu", tm.name)
      assert has_element?(view, ~s|#account-menu a[href="/users/log-out"][data-method=delete]|)
    end

    test "the account menu offers the persona switcher in dev and test", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")

      assert has_element?(view, ~s|#account-menu a[href="/dev/personas"]|)
    end

    test "pages outside the tabs get a back bar instead", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/users/settings")

      assert has_element?(view, ~s|#back-bar a[href="/"]|)
      refute has_element?(view, "#tab-bar")
    end
  end

  test "someone without a team gets the plain layout, with settings and log out", %{conn: conn} do
    {:ok, view, _html} = conn |> log_in_user(user_fixture()) |> live(~p"/no-team")

    refute has_element?(view, "#tab-bar")
    refute has_element?(view, "#app-header")
    assert has_element?(view, ~s|#account-nav a[href="/users/settings"]|)
    assert has_element?(view, ~s|#account-nav a[href="/users/log-out"][data-method=delete]|)
  end

  test "a signed-out visitor gets the plain layout, with log in", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/users/log-in")

    assert has_element?(view, ~s|#account-nav a[href="/users/log-in"]|)
  end

  test "chats needs a team", %{conn: conn} do
    assert {:error, {:redirect, %{to: "/no-team"}}} =
             conn |> log_in_user(user_fixture()) |> live(~p"/chats")
  end
end
