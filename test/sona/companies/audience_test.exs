defmodule Sona.Companies.AudienceTest do
  use Sona.DataCase, async: true

  import Sona.CompaniesFixtures
  import Sona.FeedFixtures

  alias Sona.Companies.Audience
  alias Sona.Feed

  # D-004: every encoding of the audience rule must agree. Run the four
  # shapes that include a team member, and four that don't, through the
  # query filter and through the topics.
  test "the query filter and the topics agree on every audience shape" do
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

    visible = MapSet.new(Feed.list_attention(me), & &1.id)
    topics = Audience.topics(me.team_member)

    for post <- included do
      assert post.id in visible
      assert Audience.topic(post) in topics
    end

    for post <- excluded do
      refute post.id in visible
      refute Audience.topic(post) in topics
    end

    assert length(Enum.uniq(topics)) == 4
  end
end
