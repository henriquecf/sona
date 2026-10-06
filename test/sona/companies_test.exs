defmodule Sona.CompaniesTest do
  use Sona.DataCase, async: true

  import Sona.AccountsFixtures
  import Sona.CompaniesFixtures

  alias Sona.Accounts
  alias Sona.Companies
  alias Sona.Companies.TeamMember

  @valid_attrs %{name: "Ana Costa", department: :kitchen, role: :staff}

  describe "create_site/2" do
    test "names each site once within a company" do
      company = company_fixture()
      {:ok, _} = Companies.create_site(company, %{name: "Soho"})

      assert {:error, changeset} = Companies.create_site(company, %{name: "Soho"})
      assert %{name: ["has already been taken"]} = errors_on(changeset)
    end

    test "lets another company use the same site name" do
      {:ok, _} = Companies.create_site(company_fixture(), %{name: "Soho"})

      assert {:ok, _} = Companies.create_site(company_fixture(), %{name: "Soho"})
    end
  end

  describe "create_team_member/3" do
    test "adds the user to the site's company" do
      site = site_fixture()
      user = user_fixture()

      assert {:ok, %TeamMember{} = team_member} =
               Companies.create_team_member(site, user, @valid_attrs)

      assert team_member.company_id == site.company_id
      assert team_member.site_id == site.id
      assert team_member.user_id == user.id
      assert team_member.name == "Ana Costa"
      assert team_member.department == :kitchen
      assert team_member.role == :staff
      assert team_member.left_at == nil
    end

    test "requires a name, department and role" do
      assert {:error, changeset} =
               Companies.create_team_member(site_fixture(), user_fixture(), %{})

      assert %{name: ["can't be blank"], department: ["can't be blank"], role: ["can't be blank"]} =
               errors_on(changeset)
    end

    test "rejects a department outside the list" do
      attrs = %{@valid_attrs | department: "spa"}

      assert {:error, changeset} =
               Companies.create_team_member(site_fixture(), user_fixture(), attrs)

      assert %{department: ["is invalid"]} = errors_on(changeset)
    end

    test "never takes the company, user or departure from attrs" do
      site = site_fixture()
      other_company = company_fixture()
      user = user_fixture()

      attrs =
        Map.merge(@valid_attrs, %{
          company_id: other_company.id,
          user_id: user_fixture().id,
          left_at: ~U[2026-01-01 00:00:00Z]
        })

      assert {:ok, team_member} = Companies.create_team_member(site, user, attrs)
      assert team_member.company_id == site.company_id
      assert team_member.user_id == user.id
      assert team_member.left_at == nil
    end

    test "allows one active team member per user" do
      user = user_fixture()
      team_member_fixture(user: user)

      assert {:error, changeset} =
               Companies.create_team_member(site_fixture(), user, @valid_attrs)

      assert %{user_id: ["already belongs to a team"]} = errors_on(changeset)
    end

    test "lets someone who has left join a team again" do
      user = user_fixture()

      {:ok, _} =
        Companies.offboard_team_member(team_member_fixture(user: user), DateTime.utc_now(:second))

      assert {:ok, %TeamMember{}} =
               Companies.create_team_member(site_fixture(), user, @valid_attrs)
    end
  end

  describe "the database" do
    test "rejects a team member whose site belongs to another company" do
      site = site_fixture()
      other_company = company_fixture()

      changeset =
        TeamMember.changeset(
          %TeamMember{company_id: other_company.id, site_id: site.id, user_id: user_fixture().id},
          @valid_attrs
        )

      assert {:error, changeset} = Repo.insert(changeset)
      assert %{site_id: ["does not exist"]} = errors_on(changeset)
    end
  end

  describe "get_active_team_member/1" do
    test "returns the user's team member with its company and site" do
      team_member = team_member_fixture()
      user = Accounts.get_user!(team_member.user_id)

      assert %TeamMember{id: id, company: company, site: site} =
               Companies.get_active_team_member(user)

      assert id == team_member.id
      assert company.id == team_member.company_id
      assert site.id == team_member.site_id
    end

    test "returns nil for a user who isn't on a team" do
      assert Companies.get_active_team_member(user_fixture()) == nil
    end

    test "returns nil for a user who has left" do
      team_member = team_member_fixture()
      {:ok, _} = Companies.offboard_team_member(team_member, DateTime.utc_now(:second))

      assert Companies.get_active_team_member(Accounts.get_user!(team_member.user_id)) == nil
    end
  end

  describe "offboard_team_member/2" do
    test "records when they left and expires their sessions" do
      team_member = team_member_fixture()
      user = Accounts.get_user!(team_member.user_id)
      session_token = Accounts.generate_user_session_token(user)
      left_at = ~U[2026-10-06 18:00:00Z]

      assert {:ok, {offboarded, expired_tokens}} =
               Companies.offboard_team_member(team_member, left_at)

      assert offboarded.left_at == left_at
      assert [%{token: ^session_token}] = expired_tokens
      assert Accounts.get_user_by_session_token(session_token) == nil
    end

    test "accepts the current time with microseconds" do
      assert {:ok, {offboarded, _}} =
               Companies.offboard_team_member(
                 team_member_fixture(),
                 ~U[2026-10-06 18:00:00.123456Z]
               )

      assert offboarded.left_at == ~U[2026-10-06 18:00:00Z]
    end

    test "leaves someone who already left, and their new team, untouched" do
      user = user_fixture()
      old_team_member = team_member_fixture(user: user)
      {:ok, _} = Companies.offboard_team_member(old_team_member, ~U[2026-01-01 00:00:00Z])
      team_member_fixture(user: user)
      session_token = Accounts.generate_user_session_token(user)

      assert {:error, :already_left} =
               Companies.offboard_team_member(old_team_member, ~U[2026-10-06 18:00:00Z])

      assert Repo.get!(TeamMember, old_team_member.id).left_at == ~U[2026-01-01 00:00:00Z]
      assert {_user, _} = Accounts.get_user_by_session_token(session_token)
    end
  end
end
