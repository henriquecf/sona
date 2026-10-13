defmodule Sona.Companies.AudienceTest do
  use Sona.DataCase, async: true

  import Sona.CompaniesFixtures
  import Sona.FeedFixtures

  alias Sona.Companies.Audience
  alias Sona.Feed.Post

  # D-004: every encoding of the audience rule must agree. Run the four
  # shapes that include a team member, and four that don't, through the
  # query filter, the members query and the topics.
  test "the query filter, the members and the topics agree on every audience shape" do
    company = company_fixture()
    soho = site_fixture(company: company)
    brighton = site_fixture(company: company)
    manager = company_scope_fixture(team_member_fixture(site: brighton, role: :manager))
    me = company_scope_fixture(team_member_fixture(site: soho, department: :kitchen))

    included =
      for {site, department} <- [{nil, nil}, {soho, nil}, {nil, :kitchen}, {soho, :kitchen}] do
        announcement_fixture(manager, site_id: site && site.id, department: department)
      end

    excluded =
      for {site, department} <- [{brighton, nil}, {nil, :bar}, {brighton, :kitchen}, {soho, :bar}] do
        announcement_fixture(manager, site_id: site && site.id, department: department)
      end

    # The same shapes in another company never include me.
    other_manager = company_scope_fixture(team_member_fixture(role: :manager))
    other_site = other_manager.team_member.site

    excluded =
      excluded ++
        for {site, department} <- [{nil, nil}, {other_site, nil}, {nil, :kitchen}] do
          announcement_fixture(other_manager, site_id: site && site.id, department: department)
        end

    for_me =
      MapSet.new(Repo.all(from p in Post, where: ^Audience.includes(me.team_member)), & &1.id)

    topics = Audience.topics(me.team_member)

    for post <- included do
      assert post.id in for_me
      assert me.team_member.id in members(post)
      assert Audience.topic(post) in topics
    end

    for post <- excluded do
      refute post.id in for_me
      refute me.team_member.id in members(post)
      refute Audience.topic(post) in topics
    end

    assert length(Enum.uniq(topics)) == 4
  end

  test "members are active team members only" do
    site = site_fixture()
    active = team_member_fixture(site: site)
    leaver = team_member_fixture(site: site)
    {:ok, _} = Sona.Companies.offboard_team_member(leaver, DateTime.utc_now(:second))

    assert members(%{company_id: site.company_id, site_id: site.id, department: nil}) ==
             [active.id]
  end

  defp members(record), do: Repo.all(from tm in Audience.members(record), select: tm.id)
end
