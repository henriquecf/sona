defmodule SonaWeb.PersonaControllerTest do
  use SonaWeb.ConnCase, async: true

  import Sona.CompaniesFixtures

  alias Sona.Accounts
  alias Sona.Companies

  describe "GET /dev/personas" do
    test "lists active team members across companies", %{conn: conn} do
      team_member = team_member_fixture()
      other_company_member = team_member_fixture()

      document = conn |> get(~p"/dev/personas") |> html_response(200) |> LazyHTML.from_document()

      assert has_persona?(document, team_member)
      assert has_persona?(document, other_company_member)
    end

    test "points to the seeds when there is nobody to sign in as", %{conn: conn} do
      document = conn |> get(~p"/dev/personas") |> html_response(200) |> LazyHTML.from_document()

      assert document |> LazyHTML.query("#personas-empty") |> Enum.any?()
    end

    test "leaves out team members who have left", %{conn: conn} do
      team_member = team_member_fixture()
      {:ok, _} = Companies.offboard_team_member(team_member, DateTime.utc_now(:second))

      document = conn |> get(~p"/dev/personas") |> html_response(200) |> LazyHTML.from_document()

      refute has_persona?(document, team_member)
    end
  end

  describe "POST /dev/personas/:id" do
    test "signs in as the team member's user and goes home", %{conn: conn} do
      team_member = team_member_fixture()

      conn = post(conn, ~p"/dev/personas/#{team_member}")

      assert redirected_to(conn) == ~p"/"
      assert {user, _} = Accounts.get_user_by_session_token(get_session(conn, :user_token))
      assert user.id == team_member.user_id
    end

    test "switches from one signed-in persona to another", %{conn: conn} do
      %{conn: conn} = register_and_log_in_team_member(%{conn: conn})
      other = team_member_fixture()

      conn = post(conn, ~p"/dev/personas/#{other}")

      assert redirected_to(conn) == ~p"/"
      assert {user, _} = Accounts.get_user_by_session_token(get_session(conn, :user_token))
      assert user.id == other.user_id
    end

    test "refuses a team member who has left", %{conn: conn} do
      team_member = team_member_fixture()
      {:ok, _} = Companies.offboard_team_member(team_member, DateTime.utc_now(:second))

      assert_error_sent 404, fn -> post(conn, ~p"/dev/personas/#{team_member}") end
    end
  end

  defp has_persona?(document, team_member) do
    document |> LazyHTML.query("#persona-#{team_member.id}") |> Enum.any?()
  end
end
