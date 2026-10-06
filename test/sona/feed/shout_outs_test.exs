defmodule Sona.Feed.ShoutOutsTest do
  use Sona.DataCase, async: true

  import Sona.CompaniesFixtures
  import Sona.FeedFixtures

  alias Sona.{Companies, Feed}
  alias Sona.Feed.Post

  setup do
    company = company_fixture()
    soho = site_fixture(company: company)
    brighton = site_fixture(company: company)

    %{
      company: company,
      value: company_value_fixture(company, name: "Own it"),
      me: company_scope_fixture(team_member_fixture(site: soho, department: :front_of_house)),
      colleague: company_scope_fixture(team_member_fixture(site: soho, department: :kitchen)),
      far_away: company_scope_fixture(team_member_fixture(site: brighton, department: :reception))
    }
  end

  describe "create_shout_out/2" do
    test "recognises a colleague for a company value, for the whole company", %{
      me: me,
      colleague: colleague,
      value: value
    } do
      assert {:ok, %Post{} = post} =
               Feed.create_shout_out(me, %{
                 recipient_id: colleague.team_member.id,
                 company_value_id: value.id,
                 body: "Stayed late to help with the party."
               })

      assert post.kind == :shout_out
      assert post.author_id == me.team_member.id
      assert post.recipient.id == colleague.team_member.id
      assert post.company_value.name == "Own it"
      assert {post.site_id, post.department} == {nil, nil}
    end

    test "needs a message", %{me: me, colleague: colleague, value: value} do
      assert {:error, changeset} =
               Feed.create_shout_out(me, %{
                 recipient_id: colleague.team_member.id,
                 company_value_id: value.id
               })

      assert %{body: ["can't be blank"]} = errors_on(changeset)
    end

    test "refuses yourself, someone who has left, and another company's team member", %{
      me: me,
      colleague: colleague,
      value: value
    } do
      {:ok, _} = Companies.offboard_team_member(colleague.team_member, DateTime.utc_now(:second))
      stranger = team_member_fixture()

      for recipient_id <- [me.team_member.id, colleague.team_member.id, stranger.id] do
        assert {:error, changeset} =
                 Feed.create_shout_out(me, %{
                   recipient_id: recipient_id,
                   company_value_id: value.id,
                   body: "Thanks!"
                 })

        assert %{recipient_id: ["isn't one of your colleagues"]} = errors_on(changeset)
      end
    end

    test "refuses another company's value", %{me: me, colleague: colleague} do
      other_value = company_value_fixture(company_fixture())

      assert {:error, changeset} =
               Feed.create_shout_out(me, %{
                 recipient_id: colleague.team_member.id,
                 company_value_id: other_value.id,
                 body: "Thanks!"
               })

      assert %{company_value_id: ["does not exist"]} = errors_on(changeset)
    end
  end

  describe "in the feed" do
    test "everyone in the company sees it, never as needing attention; nobody else does", %{
      me: me,
      colleague: colleague,
      far_away: far_away,
      value: value
    } do
      post = shout_out_fixture(me, colleague.team_member, value)
      outsider = company_scope_fixture()

      for scope <- [me, colleague, far_away] do
        assert Enum.map(Feed.list_feed(scope), & &1.id) == [post.id]
        assert Feed.list_attention(scope) == []
      end

      assert Feed.list_feed(outsider) == []
    end

    test "reaches everyone in the company live", %{
      me: me,
      colleague: colleague,
      far_away: far_away,
      value: value
    } do
      Feed.subscribe(far_away)

      post = shout_out_fixture(me, colleague.team_member, value)

      assert_receive {:post_created, %Post{id: id, kind: :shout_out}}
      assert id == post.id
    end

    test "can't be acknowledged", %{me: me, colleague: colleague, value: value} do
      post = shout_out_fixture(me, colleague.team_member, value)

      assert_raise Ecto.NoResultsError, fn -> Feed.acknowledge(colleague, post.id) end
    end
  end

  describe "the database" do
    test "Post.shout_out_changeset turns a shout-out to yourself into an error", %{
      me: me,
      value: value
    } do
      assert {:error, changeset} =
               %Post{company_id: me.team_member.company_id, author_id: me.team_member.id}
               |> Post.shout_out_changeset(%{
                 recipient_id: me.team_member.id,
                 company_value_id: value.id,
                 body: "Me!"
               })
               |> Repo.insert()

      assert %{recipient_id: ["is invalid"]} = errors_on(changeset)
    end

    test "Post.shout_out_changeset turns another company's recipient into an error", %{
      me: me,
      value: value
    } do
      stranger = team_member_fixture()

      assert {:error, changeset} =
               %Post{company_id: me.team_member.company_id, author_id: me.team_member.id}
               |> Post.shout_out_changeset(%{
                 recipient_id: stranger.id,
                 company_value_id: value.id,
                 body: "Hi"
               })
               |> Repo.insert()

      assert %{recipient_id: ["does not exist"]} = errors_on(changeset)
    end

    test "rejects every post that is neither a whole announcement nor a whole shout-out", %{
      me: me,
      colleague: colleague,
      value: value
    } do
      shout_out = %{
        kind: :shout_out,
        recipient_id: colleague.team_member.id,
        company_value_id: value.id
      }

      announcement = %{kind: :announcement, title: "Rota"}

      for {label, fields} <- [
            {"a shout-out with a title", Map.put(shout_out, :title, "Title")},
            {"a shout-out for one site", Map.put(shout_out, :site_id, me.team_member.site_id)},
            {"a shout-out for one department", Map.put(shout_out, :department, :kitchen)},
            {"a shout-out without a recipient", Map.put(shout_out, :recipient_id, nil)},
            {"a shout-out without a value", Map.put(shout_out, :company_value_id, nil)},
            {"an announcement with a recipient",
             Map.put(announcement, :recipient_id, colleague.team_member.id)},
            {"an announcement with a value", Map.put(announcement, :company_value_id, value.id)}
          ] do
        changeset =
          %Post{company_id: me.team_member.company_id, author_id: me.team_member.id, body: "x"}
          |> Ecto.Changeset.change(fields)
          |> Ecto.Changeset.check_constraint(:kind, name: :post_shape)

        assert {:error, changeset} = Repo.insert(changeset), label
        assert %{kind: ["is invalid"]} = errors_on(changeset), label
      end
    end
  end
end
