defmodule Sona.Feed.AnnouncementStatsTest do
  use Sona.DataCase, async: true

  import Sona.CompaniesFixtures
  import Sona.FeedFixtures

  alias Sona.{Companies, Feed}
  alias Sona.Feed.{AnnouncementStats, Delivery}

  setup do
    company = company_fixture()
    soho = site_fixture(company: company)
    brighton = site_fixture(company: company)

    %{
      company: company,
      soho: soho,
      brighton: brighton,
      author: company_scope_fixture(team_member_fixture(site: soho, role: :manager)),
      # Outside the audience of anything posted to Soho.
      manager: company_scope_fixture(team_member_fixture(site: brighton, role: :manager)),
      staff: company_scope_fixture(team_member_fixture(site: brighton))
    }
  end

  describe "get_announcement_stats!/2 and list_deliveries/2" do
    setup :announcement_to_soho

    test "count who it was sent to, saw it, acknowledged it and left without", %{
      manager: manager,
      post: post
    } do
      assert %AnnouncementStats{sent: 5, seen: 3, acknowledged: 2, left: 1} =
               Feed.get_announcement_stats!(manager, post.id)
    end

    test "group everyone it was sent to, agreeing with the counts", %{
      manager: manager,
      post: post,
      people: people
    } do
      stats = Feed.get_announcement_stats!(manager, post.id)
      groups = manager |> Feed.list_deliveries(post) |> Enum.group_by(&Delivery.status/1)

      assert ids(groups.not_seen) == [people.not_seen.id]
      assert ids(groups.seen) == [people.seen.id]
      assert ids(groups.acknowledged) == Enum.sort([people.acknowledged.id, people.gone.id])
      assert ids(groups.left) == [people.left.id]

      assert stats.sent == length(Enum.concat(Map.values(groups)))
      assert stats.seen == length(groups.seen) + length(groups.acknowledged)
      assert stats.acknowledged == length(groups.acknowledged)
      assert stats.left == length(groups.left)
    end

    test "are zero for an announcement that reached nobody", %{
      manager: manager,
      author: author,
      brighton: brighton
    } do
      post = announcement_fixture(author, site_id: brighton.id, department: :housekeeping)

      assert %AnnouncementStats{sent: 0, seen: 0, acknowledged: 0, left: 0} =
               Feed.get_announcement_stats!(manager, post.id)

      assert Feed.list_deliveries(manager, post) == []
    end

    test "don't find another company's announcement or a shout-out", %{
      manager: manager,
      staff: staff
    } do
      other_manager = company_scope_fixture(team_member_fixture(role: :manager))
      _reader = team_member_fixture(site: other_manager.team_member.site)
      elsewhere = announcement_fixture(other_manager)
      value = company_value_fixture(manager.team_member.company)
      shout_out = shout_out_fixture(staff, manager.team_member, value)

      assert_raise Ecto.NoResultsError, fn ->
        Feed.get_announcement_stats!(manager, elsewhere.id)
      end

      assert_raise Ecto.NoResultsError, fn ->
        Feed.get_announcement_stats!(manager, shout_out.id)
      end

      assert Feed.list_deliveries(manager, elsewhere) == []
    end

    test "are for managers only", %{staff: staff, post: post} do
      assert_raise FunctionClauseError, fn -> Feed.get_announcement_stats!(staff, post.id) end
      assert_raise FunctionClauseError, fn -> Feed.list_deliveries(staff, post) end
    end
  end

  describe "list_announcement_stats/2" do
    test "lists every announcement in the company, newest first, whatever its audience", %{
      manager: manager,
      author: author,
      staff: staff,
      soho: soho
    } do
      for_soho = announcement_fixture(author, site_id: soho.id)
      for_everyone = announcement_fixture(author)
      value = company_value_fixture(manager.team_member.company)
      _shout_out = shout_out_fixture(staff, manager.team_member, value)

      _elsewhere =
        announcement_fixture(company_scope_fixture(team_member_fixture(role: :manager)))

      assert [%AnnouncementStats{post: newest}, %AnnouncementStats{post: oldest}] =
               Feed.list_announcement_stats(manager)

      assert {newest.id, oldest.id} == {for_everyone.id, for_soho.id}
      assert newest.author.id == author.team_member.id
      # Each gets its own counts: Soho has nobody but the author.
      assert manager |> Feed.list_announcement_stats() |> Enum.map(& &1.sent) == [2, 0]
    end

    test "pages by id", %{manager: manager, author: author} do
      [first, second, third] = for _ <- 1..3, do: announcement_fixture(author)

      assert post_ids(Feed.list_announcement_stats(manager, limit: 2)) == [third.id, second.id]
      assert post_ids(Feed.list_announcement_stats(manager, before: second.id)) == [first.id]
    end

    test "counts like get_announcement_stats!/2", %{manager: manager} = context do
      %{post: post} = announcement_to_soho(context)

      assert Feed.list_announcement_stats(manager) == [
               Feed.get_announcement_stats!(manager, post.id)
             ]
    end

    test "is for managers only", %{staff: staff} do
      assert_raise FunctionClauseError, fn -> Feed.list_announcement_stats(staff) end
    end
  end

  describe "subscribe_to_stats/1" do
    test "tells managers which announcement's stats changed, once per change", %{
      manager: manager,
      author: author,
      soho: soho
    } do
      reader = company_scope_fixture(team_member_fixture(site: soho))
      Feed.subscribe_to_stats(manager)

      post = announcement_fixture(author, site_id: soho.id)
      assert_receive {:announcement_stats_changed, id}
      assert id == post.id

      :ok = Feed.mark_seen(reader, [post])
      assert_receive {:announcement_stats_changed, ^id}
      :ok = Feed.mark_seen(reader, [post])
      refute_received {:announcement_stats_changed, _}

      {:ok, _} = Feed.acknowledge(reader, post.id)
      assert_receive {:announcement_stats_changed, ^id}
      {:ok, _} = Feed.acknowledge(reader, post.id)
      refute_received {:announcement_stats_changed, _}
    end

    test "never tells them about another company", %{manager: manager} do
      Feed.subscribe_to_stats(manager)
      other_manager = company_scope_fixture(team_member_fixture(role: :manager))
      reader = company_scope_fixture(team_member_fixture(site: other_manager.team_member.site))

      post = announcement_fixture(other_manager)
      :ok = Feed.mark_seen(reader, [post])
      {:ok, _} = Feed.acknowledge(reader, post.id)

      refute_received {:announcement_stats_changed, _}
    end

    test "is for managers only", %{staff: staff} do
      assert_raise FunctionClauseError, fn -> Feed.subscribe_to_stats(staff) end
    end
  end

  # An announcement to Soho, sent to five people: one who hasn't seen it,
  # one who has, one who acknowledged it, one who saw it and left without
  # acknowledging, and one who acknowledged it and then left ("gone").
  defp announcement_to_soho(%{author: author, soho: soho}) do
    people =
      for name <- [:not_seen, :seen, :acknowledged, :left, :gone], into: %{} do
        {name, team_member_fixture(site: soho)}
      end

    scope =
      Map.new(people, fn {name, team_member} -> {name, company_scope_fixture(team_member)} end)

    post = announcement_fixture(author, site_id: soho.id)

    :ok = Feed.mark_seen(scope.seen, [post])
    :ok = Feed.mark_seen(scope.left, [post])
    {:ok, _} = Feed.acknowledge(scope.acknowledged, post.id)
    {:ok, _} = Feed.acknowledge(scope.gone, post.id)

    for name <- [:left, :gone] do
      {:ok, _} = Companies.offboard_team_member(people[name], DateTime.utc_now(:second))
    end

    %{post: post, people: people}
  end

  defp ids(deliveries), do: deliveries |> Enum.map(& &1.team_member.id) |> Enum.sort()
  defp post_ids(stats), do: Enum.map(stats, & &1.post.id)
end
