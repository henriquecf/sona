defmodule SonaWeb.HomeLiveTest do
  use SonaWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Sona.AccountsFixtures
  import Sona.CompaniesFixtures

  alias Sona.Accounts
  alias Sona.Companies

  describe "an active team member" do
    test "sees home, greeted by first name", %{conn: conn} do
      team_member = team_member_fixture(name: "Ana Costa")
      conn = log_in_user(conn, Accounts.get_user!(team_member.user_id))

      {:ok, view, _html} = live(conn, ~p"/")

      assert has_element?(view, "#home")
      assert has_element?(view, "#home-greeting", "Ana")
      refute has_element?(view, "#home-greeting", "Costa")
    end
  end

  test "a signed-out visitor is sent to log in", %{conn: conn} do
    assert {:error, {:redirect, %{to: "/users/log-in"}}} = live(conn, ~p"/")
  end

  test "a user who isn't on a team is sent to /no-team", %{conn: conn} do
    conn = log_in_user(conn, user_fixture())

    assert {:error, {:redirect, %{to: "/no-team"}}} = live(conn, ~p"/")
  end

  test "leaving signs the team member out", %{conn: conn} do
    team_member = team_member_fixture()
    conn = log_in_user(conn, Accounts.get_user!(team_member.user_id))
    {:ok, _} = Companies.offboard_team_member(team_member, DateTime.utc_now(:second))

    assert {:error, {:redirect, %{to: "/users/log-in"}}} = live(conn, ~p"/")
  end

  test "someone who has left and signs in again is sent to /no-team", %{conn: conn} do
    team_member = team_member_fixture()
    {:ok, _} = Companies.offboard_team_member(team_member, DateTime.utc_now(:second))
    conn = log_in_user(conn, Accounts.get_user!(team_member.user_id))

    assert {:error, {:redirect, %{to: "/no-team"}}} = live(conn, ~p"/")
  end
end
