defmodule SonaWeb.NewShoutOutLiveTest do
  use SonaWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Sona.CompaniesFixtures

  alias Sona.Feed

  setup :register_and_log_in_team_member

  setup %{team_member: me} do
    %{
      colleague: team_member_fixture(site: me.site, name: "Kwame Mensah"),
      value: company_value_fixture(me.company, name: "Own it")
    }
  end

  test "offers your colleagues and your company's values", %{
    conn: conn,
    team_member: me,
    colleague: colleague,
    value: value
  } do
    stranger = team_member_fixture()
    other_value = company_value_fixture(company_fixture())

    {:ok, view, _html} = live(conn, ~p"/shout-outs/new")

    assert has_element?(view, ~s|#post_recipient_id option[value="#{colleague.id}"]|)
    refute has_element?(view, ~s|#post_recipient_id option[value="#{me.id}"]|)
    refute has_element?(view, ~s|#post_recipient_id option[value="#{stranger.id}"]|)
    assert has_element?(view, ~s|#value-#{value.id}|)
    refute has_element?(view, ~s|#value-#{other_value.id}|)
  end

  test "posts the shout-out and goes home, where it shows in the feed", %{
    conn: conn,
    scope: scope,
    colleague: colleague,
    value: value
  } do
    {:ok, view, _html} = live(conn, ~p"/shout-outs/new")

    assert {:error, {:live_redirect, %{to: "/"}}} =
             view
             |> form("#shout-out-form",
               post: %{
                 recipient_id: colleague.id,
                 company_value_id: value.id,
                 body: "Saved the party tonight"
               }
             )
             |> render_submit()

    assert [post] = Feed.list_feed(scope)
    {:ok, home, _html} = live(conn, ~p"/")
    assert has_element?(home, "#feed-#{post.id}[data-kind=shout_out]", "Kwame Mensah")
    assert has_element?(home, "#feed-#{post.id}", "Own it")
  end

  test "a forged colleague id from another company is refused", %{
    conn: conn,
    scope: scope,
    value: value
  } do
    stranger = team_member_fixture()
    {:ok, view, _html} = live(conn, ~p"/shout-outs/new")

    render_submit(view, "post", %{
      "post" => %{
        "recipient_id" => "#{stranger.id}",
        "company_value_id" => "#{value.id}",
        "body" => "Hi"
      }
    })

    assert Feed.list_feed(scope) == []
    assert has_element?(view, "#shout-out-form", "isn't one of your colleagues")
  end

  test "a colleague's shout-out arrives live on Home", %{
    conn: conn,
    team_member: me,
    colleague: colleague,
    value: value
  } do
    {:ok, home, _html} = live(conn, ~p"/")

    post =
      Sona.FeedFixtures.shout_out_fixture(company_scope_fixture(colleague), me, value,
        body: "Thanks for covering my shift!"
      )

    assert has_element?(home, "#feed-#{post.id}[data-kind=shout_out]", "Thanks for covering")
  end
end
