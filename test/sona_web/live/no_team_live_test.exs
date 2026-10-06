defmodule SonaWeb.NoTeamLiveTest do
  use SonaWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Sona.AccountsFixtures

  test "tells a user who isn't on a team to ask their manager", %{conn: conn} do
    {:ok, view, _html} = conn |> log_in_user(user_fixture()) |> live(~p"/no-team")

    assert has_element?(view, "#no-team")
  end

  describe "an active team member" do
    setup :register_and_log_in_team_member

    test "is sent home", %{conn: conn} do
      assert {:error, {:redirect, %{to: "/"}}} = live(conn, ~p"/no-team")
    end
  end

  test "a signed-out visitor is sent to log in", %{conn: conn} do
    assert {:error, {:redirect, %{to: "/users/log-in"}}} = live(conn, ~p"/no-team")
  end
end
