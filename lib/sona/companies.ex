defmodule Sona.Companies do
  @moduledoc """
  Companies, their sites, and the team members who work at them.

  Creating companies, sites and team members, and offboarding, are
  provisioning operations: there is no acting team member yet, so they
  take no scope. Seeds and the console call them until the manager view
  adds scoped versions (D-003).
  """

  import Ecto.Query, warn: false

  alias Sona.Accounts
  alias Sona.Accounts.{Scope, User}
  alias Sona.Companies.{Company, CompanyValue, Site, TeamMember}
  alias Sona.Repo

  def create_company(attrs) do
    %Company{}
    |> Company.changeset(attrs)
    |> Repo.insert()
  end

  def create_site(%Company{} = company, attrs) do
    %Site{company_id: company.id}
    |> Site.changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Adds `user` to the company that owns `site`, working at that site.
  """
  def create_team_member(%Site{} = site, %User{} = user, attrs) do
    %TeamMember{company_id: site.company_id, site_id: site.id, user_id: user.id}
    |> TeamMember.changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Returns the user's active team member, with its company and site, or
  `nil` if they aren't on a team. `SonaWeb.UserAuth` puts it in the scope.
  """
  def get_active_team_member(%User{} = user) do
    Repo.one(
      from tm in TeamMember,
        join: c in assoc(tm, :company),
        join: s in assoc(tm, :site),
        where: tm.user_id == ^user.id and is_nil(tm.left_at),
        preload: [company: c, site: s]
    )
  end

  @doc """
  Adds one of the values a company stands for, which shout-outs recognise.
  A provisioning operation, like creating sites.
  """
  def create_value(%Company{} = company, attrs) do
    %CompanyValue{company_id: company.id}
    |> CompanyValue.changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Returns the values of the scope's company, by name.
  """
  def list_values(%Scope{team_member: %TeamMember{company_id: company_id}}) do
    Repo.all(from v in CompanyValue, where: v.company_id == ^company_id, order_by: v.name)
  end

  @doc """
  Returns the sites of the scope's company, by name.
  """
  def list_sites(%Scope{team_member: %TeamMember{company_id: company_id}}) do
    Repo.all(from s in Site, where: s.company_id == ^company_id, order_by: s.name)
  end

  @doc """
  Returns the scope's active colleagues (everyone else active in the
  company), by site and name, with their site.
  """
  def list_colleagues(%Scope{team_member: %TeamMember{} = team_member}) do
    Repo.all(
      from tm in colleagues(team_member),
        join: s in assoc(tm, :site),
        order_by: [s.name, tm.name],
        preload: [site: s]
    )
  end

  @doc """
  Gets one of the scope's active colleagues, or `nil` for any other id:
  yourself, someone who has left, or another company's team member.
  """
  def get_colleague(%Scope{team_member: %TeamMember{} = team_member}, id) do
    Repo.get(colleagues(team_member), id)
  end

  defp colleagues(%TeamMember{} = team_member) do
    from tm in TeamMember,
      where: tm.company_id == ^team_member.company_id,
      where: is_nil(tm.left_at) and tm.id != ^team_member.id
  end

  @doc """
  Records that an active team member left at `left_at` and deletes their
  user's tokens.

  Returns `{:ok, {team_member, expired_tokens}}`. The web layer passes the
  tokens to `SonaWeb.UserAuth.disconnect_sessions/1` so open tabs lose
  access at once. Returns `{:error, :already_left}` for someone who has
  already left, even from a stale struct, so a repeat can't sign the user
  out of a team they have joined since.
  """
  def offboard_team_member(%TeamMember{} = team_member, %DateTime{} = left_at) do
    left_at = DateTime.truncate(left_at, :second)

    Repo.transact(fn ->
      query =
        from tm in TeamMember,
          where: tm.id == ^team_member.id and is_nil(tm.left_at),
          select: tm

      case Repo.update_all(query, set: [left_at: left_at, updated_at: DateTime.utc_now(:second)]) do
        {1, [team_member]} ->
          user = Accounts.get_user!(team_member.user_id)
          {:ok, {team_member, Accounts.delete_all_user_tokens(user)}}

        {0, []} ->
          {:error, :already_left}
      end
    end)
  end
end
