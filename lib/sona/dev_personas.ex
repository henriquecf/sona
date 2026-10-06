# Dev-only (D-005): compiled only with dev routes, so it never ships to production.
if Application.compile_env(:sona, :dev_routes) do
  defmodule Sona.DevPersonas do
    @moduledoc """
    Backs the dev-only persona switcher (D-005).

    These are the only unscoped reads of team members: they cross every
    company so a demo can sign in as anyone. Like the persona routes, this
    module is only compiled when `dev_routes` is on.
    """

    import Ecto.Query, warn: false

    alias Sona.Accounts.User
    alias Sona.Companies.TeamMember
    alias Sona.Repo

    @doc """
    Returns every active team member, with company and site, ordered by
    company, site and name.
    """
    def list_team_members do
      Repo.all(
        from tm in TeamMember,
          join: c in assoc(tm, :company),
          join: s in assoc(tm, :site),
          where: is_nil(tm.left_at),
          order_by: [c.name, c.id, s.name, tm.name],
          preload: [company: c, site: s]
      )
    end

    @doc """
    Returns the user behind an active team member. Raises if there is none.
    """
    def get_user_by_team_member!(team_member_id) do
      Repo.one!(
        from u in User,
          join: tm in TeamMember,
          on: tm.user_id == u.id,
          where: tm.id == ^team_member_id and is_nil(tm.left_at)
      )
    end
  end
end
