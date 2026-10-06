defmodule Sona.CompaniesFixtures do
  @moduledoc """
  This module defines test helpers for creating
  entities via the `Sona.Companies` context.
  """

  import Sona.AccountsFixtures

  alias Sona.Accounts.Scope
  alias Sona.Companies

  def company_fixture(attrs \\ %{}) do
    {:ok, company} =
      attrs
      |> Enum.into(%{name: "Company #{System.unique_integer([:positive])}"})
      |> Companies.create_company()

    company
  end

  def site_fixture(attrs \\ %{}) do
    {company, attrs} = Map.pop_lazy(Map.new(attrs), :company, &company_fixture/0)

    {:ok, site} =
      Companies.create_site(
        company,
        Enum.into(attrs, %{name: "Site #{System.unique_integer([:positive])}"})
      )

    site
  end

  def team_member_fixture(attrs \\ %{}) do
    attrs = Map.new(attrs)
    {site, attrs} = Map.pop_lazy(attrs, :site, &site_fixture/0)
    {user, attrs} = Map.pop_lazy(attrs, :user, &user_fixture/0)

    {:ok, team_member} =
      Companies.create_team_member(
        site,
        user,
        Enum.into(attrs, %{
          name: "Team member #{System.unique_integer([:positive])}",
          department: :front_of_house,
          role: :staff
        })
      )

    team_member
  end

  @doc """
  The scope a signed-in team member acts with, as `SonaWeb.UserAuth` builds it.
  """
  def company_scope_fixture(team_member \\ team_member_fixture()) do
    user = Sona.Accounts.get_user!(team_member.user_id)

    user
    |> Scope.for_user()
    |> Scope.put_team_member(Companies.get_active_team_member(user))
  end
end
