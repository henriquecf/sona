defmodule Sona.FeedTest do
  use Sona.DataCase, async: true

  import Sona.CompaniesFixtures
  import Sona.FeedFixtures

  alias Sona.Feed
  alias Sona.Feed.Post

  setup do
    company = company_fixture()
    soho = site_fixture(company: company)
    brighton = site_fixture(company: company)

    %{
      company: company,
      soho: soho,
      brighton: brighton,
      manager: company_scope_fixture(team_member_fixture(site: soho, role: :manager)),
      me: company_scope_fixture(team_member_fixture(site: soho, department: :kitchen))
    }
  end

  describe "create_announcement/2" do
    test "lets a manager post to an audience", %{manager: manager, soho: soho} do
      assert {:ok, %Post{} = post} =
               Feed.create_announcement(manager, %{
                 title: "Fridge 2",
                 body: "The engineer comes at 3pm.",
                 site_id: soho.id,
                 department: :kitchen
               })

      assert post.kind == :announcement
      assert post.author_id == manager.team_member.id
      assert post.company_id == manager.team_member.company_id
      assert {post.site_id, post.department} == {soho.id, :kitchen}
    end

    test "is for managers only", %{me: me} do
      assert {:error, :unauthorized} =
               Feed.create_announcement(me, %{title: "Hi", body: "Hello everyone"})
    end

    test "needs a title and a body", %{manager: manager} do
      assert {:error, changeset} = Feed.create_announcement(manager, %{})
      assert %{title: ["can't be blank"], body: ["can't be blank"]} = errors_on(changeset)
    end

    test "never takes the author or company from attrs", %{manager: manager, me: me} do
      other_company = company_fixture()

      post =
        announcement_fixture(manager, author_id: me.team_member.id, company_id: other_company.id)

      assert post.author_id == manager.team_member.id
      assert post.company_id == manager.team_member.company_id
    end

    test "rejects a department outside the list", %{manager: manager} do
      assert {:error, changeset} =
               Feed.create_announcement(manager, %{title: "Hi", body: "Hello", department: "chef"})

      assert %{department: ["is invalid"]} = errors_on(changeset)
    end

    test "rejects a site from another company", %{manager: manager} do
      assert {:error, changeset} =
               Feed.create_announcement(manager, %{
                 title: "Hi",
                 body: "Hello",
                 site_id: site_fixture().id
               })

      assert %{site_id: ["does not exist"]} = errors_on(changeset)
    end
  end

  describe "list_attention/1 and list_feed/2" do
    test "show only announcements for your audience, plus your own", %{
      manager: manager,
      me: me,
      brighton: brighton
    } do
      for_me = announcement_fixture(manager, title: "For everyone")
      for_kitchens = announcement_fixture(manager, title: "Kitchens", department: :kitchen)
      _for_brighton = announcement_fixture(manager, title: "Brighton", site_id: brighton.id)
      _for_bars = announcement_fixture(manager, title: "Bars", department: :bar)
      other_manager = company_scope_fixture(team_member_fixture(role: :manager))
      _other_company = announcement_fixture(other_manager, title: "Elsewhere")

      assert ids(Feed.list_attention(me)) == [for_kitchens.id, for_me.id]
      assert Feed.list_feed(me) == []

      # The author sees their own announcements in the feed, never as needing attention.
      assert Feed.list_attention(manager) == []

      assert manager |> Feed.list_feed() |> Enum.map(& &1.title) ==
               ["Bars", "Brighton", "Kitchens", "For everyone"]
    end

    test "acknowledging moves an announcement from attention to the feed", %{
      manager: manager,
      me: me
    } do
      post = announcement_fixture(manager)

      assert {:ok, acknowledged} = Feed.acknowledge(me, post.id)
      assert acknowledged.acknowledged_at

      assert Feed.list_attention(me) == []
      assert [%Post{id: id, acknowledged_at: %DateTime{}}] = Feed.list_feed(me)
      assert id == post.id
    end

    test "announcements from before you joined don't need your attention", %{
      manager: manager,
      soho: soho
    } do
      post = announcement_fixture(manager)
      newcomer = team_member_fixture(site: soho)

      Repo.update_all(from(t in Sona.Companies.TeamMember, where: t.id == ^newcomer.id),
        set: [inserted_at: DateTime.add(DateTime.utc_now(:second), 60)]
      )

      newcomer = company_scope_fixture(newcomer)
      assert Feed.list_attention(newcomer) == []
      assert ids(Feed.list_feed(newcomer)) == [post.id]
    end

    test "the feed pages by id, newest first", %{manager: manager} do
      [first, second, third] = for n <- 1..3, do: announcement_fixture(manager, title: "#{n}")

      assert ids(Feed.list_feed(manager, limit: 2)) == [third.id, second.id]
      assert ids(Feed.list_feed(manager, before: second.id, limit: 2)) == [first.id]
    end
  end

  describe "acknowledge/2" do
    test "records once, keeping the first time", %{manager: manager, me: me} do
      post = announcement_fixture(manager)

      {:ok, _first} = Feed.acknowledge(me, post.id)
      # Backdate it, so a second write would show.
      Repo.update_all(Sona.Feed.Acknowledgement, set: [inserted_at: ~U[2026-01-01 00:00:00Z]])
      {:ok, again} = Feed.acknowledge(me, post.id)

      assert again.acknowledged_at == ~U[2026-01-01 00:00:00Z]
      assert Repo.aggregate(Sona.Feed.Acknowledgement, :count) == 1
    end

    test "refuses an announcement outside your audience or company", %{
      manager: manager,
      me: me,
      brighton: brighton
    } do
      brighton_post = announcement_fixture(manager, site_id: brighton.id)
      other_manager = company_scope_fixture(team_member_fixture(role: :manager))
      other_company_post = announcement_fixture(other_manager)

      assert_raise Ecto.NoResultsError, fn -> Feed.acknowledge(me, brighton_post.id) end
      assert_raise Ecto.NoResultsError, fn -> Feed.acknowledge(me, other_company_post.id) end
    end

    test "refuses your own announcement", %{manager: manager} do
      post = announcement_fixture(manager)

      assert_raise Ecto.NoResultsError, fn -> Feed.acknowledge(manager, post.id) end
    end
  end

  describe "the database" do
    test "rejects an announcement without a title", %{manager: manager} do
      changeset =
        %Post{
          company_id: manager.team_member.company_id,
          author_id: manager.team_member.id,
          kind: :announcement
        }
        |> Ecto.Changeset.change(body: "No title")
        |> Ecto.Changeset.check_constraint(:title, name: :post_shape)

      assert {:error, changeset} = Repo.insert(changeset)
      assert %{title: ["is invalid"]} = errors_on(changeset)
    end
  end

  describe "subscribe/1" do
    test "delivers new posts for your audience, and only those", %{
      manager: manager,
      me: me,
      brighton: brighton
    } do
      Feed.subscribe(me)

      post = announcement_fixture(manager, department: :kitchen)
      announcement_fixture(manager, site_id: brighton.id)
      announcement_fixture(manager, department: :bar)
      other_company_manager = company_scope_fixture(team_member_fixture(role: :manager))
      announcement_fixture(other_company_manager, title: "To everyone, elsewhere")
      announcement_fixture(other_company_manager, department: :kitchen)

      assert_receive {:post_created, %Post{id: id}}
      assert id == post.id
      refute_receive {:post_created, _}
    end
  end

  defp ids(posts), do: Enum.map(posts, & &1.id)
end
