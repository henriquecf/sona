# Dev-only (D-005): compiled only with dev routes, so it never ships to production.
if Application.compile_env(:sona, :dev_routes) do
  defmodule SonaWeb.PersonaController do
    @moduledoc """
    The dev-only persona switcher (D-005): sign in as any seeded team member.
    Routed only when `dev_routes` is enabled, so it never reaches production.
    """
    use SonaWeb, :controller

    alias Sona.DevPersonas
    alias SonaWeb.UserAuth

    def index(conn, _params) do
      team_members = DevPersonas.list_team_members()
      render(conn, :index, companies: Enum.chunk_by(team_members, & &1.company_id))
    end

    def create(conn, %{"id" => team_member_id}) do
      user = DevPersonas.get_user_by_team_member!(team_member_id)

      # Send every persona home. Without a return path, log_in_user/2 sends
      # someone who is already signed in to the settings page instead.
      conn
      |> put_session(:user_return_to, ~p"/")
      |> UserAuth.log_in_user(user)
    end
  end
end
