defmodule Sona.ChatTest do
  use Sona.DataCase, async: true

  import Sona.ChatFixtures
  import Sona.CompaniesFixtures

  alias Sona.Chat
  alias Sona.Chat.Message

  setup do
    company = company_fixture()
    soho = site_fixture(company: company, name: "Soho")
    brighton = site_fixture(company: company, name: "Brighton")
    team_member = team_member_fixture(site: soho, department: :kitchen)

    %{
      company: company,
      soho: soho,
      brighton: brighton,
      scope: company_scope_fixture(team_member)
    }
  end

  describe "create_channel/2" do
    test "creates a named channel for an audience", %{company: company, soho: soho} do
      assert {:ok, channel} =
               Chat.create_channel(company, %{
                 name: "Soho kitchen",
                 site_id: soho.id,
                 department: :kitchen
               })

      assert channel.kind == :channel
      assert channel.company_id == company.id
      assert channel.site_id == soho.id
      assert channel.department == :kitchen
    end

    test "requires a name", %{company: company} do
      assert {:error, changeset} = Chat.create_channel(company, %{})
      assert %{name: ["can't be blank"]} = errors_on(changeset)
    end

    test "names each channel once within a company", %{company: company} do
      channel_fixture(company: company, name: "Everyone")

      assert {:error, changeset} = Chat.create_channel(company, %{name: "Everyone"})
      assert %{name: ["has already been taken"]} = errors_on(changeset)
      assert {:ok, _} = Chat.create_channel(company_fixture(), %{name: "Everyone"})
    end

    test "rejects a site from another company", %{company: company} do
      other_site = site_fixture()

      assert {:error, changeset} =
               Chat.create_channel(company, %{name: "Elsewhere", site_id: other_site.id})

      assert %{site_id: ["does not exist"]} = errors_on(changeset)
    end
  end

  describe "list_conversations/1" do
    test "shows exactly the channels whose audience includes you", %{
      company: company,
      soho: soho,
      brighton: brighton,
      scope: scope
    } do
      channel_fixture(company: company, name: "Everyone")
      channel_fixture(company: company, name: "Soho", site_id: soho.id)
      channel_fixture(company: company, name: "Kitchens", department: :kitchen)

      channel_fixture(
        company: company,
        name: "Soho kitchen",
        site_id: soho.id,
        department: :kitchen
      )

      channel_fixture(company: company, name: "Brighton", site_id: brighton.id)
      channel_fixture(company: company, name: "Bars", department: :bar)

      channel_fixture(
        company: company,
        name: "Brighton kitchen",
        site_id: brighton.id,
        department: :kitchen
      )

      channel_fixture(name: "Another company")

      assert scope |> Chat.list_conversations() |> Enum.map(& &1.name) ==
               ["Everyone", "Kitchens", "Soho", "Soho kitchen"]
    end
  end

  describe "list_conversations/1 activity" do
    test "puts the most recently active first, each with its latest message and author", %{
      company: company,
      scope: scope
    } do
      quiet = channel_fixture(company: company, name: "A quiet channel")
      busy = channel_fixture(company: company, name: "Busy")
      later = channel_fixture(company: company, name: "Later")
      message_fixture(scope, busy, body: "first")
      message_fixture(scope, later, body: "second")
      latest = message_fixture(scope, busy, body: "third")

      assert [first, second, third] = Chat.list_conversations(scope)
      assert {first.id, second.id, third.id} == {busy.id, later.id, quiet.id}
      assert first.last_message.id == latest.id
      assert first.last_message.author.name == scope.team_member.name
      assert third.last_message == nil
    end
  end

  describe "get_conversation!/2" do
    test "returns a channel in your audience", %{company: company, scope: scope} do
      channel = channel_fixture(company: company)

      assert Chat.get_conversation!(scope, channel.id).id == channel.id
    end

    test "refuses a channel outside your audience", %{
      company: company,
      brighton: brighton,
      scope: scope
    } do
      channel = channel_fixture(company: company, site_id: brighton.id)

      assert_raise Ecto.NoResultsError, fn -> Chat.get_conversation!(scope, channel.id) end
    end

    test "refuses another company's channel", %{scope: scope} do
      channel = channel_fixture()

      assert_raise Ecto.NoResultsError, fn -> Chat.get_conversation!(scope, channel.id) end
    end
  end

  describe "send_message/3" do
    setup %{company: company} do
      %{channel: channel_fixture(company: company)}
    end

    test "posts as the scope's team member", %{scope: scope, channel: channel} do
      other = team_member_fixture()

      assert {:ok, %Message{} = message} =
               Chat.send_message(scope, channel, %{
                 body: "Fridge 2 is fixed",
                 author_id: other.id,
                 conversation_id: channel_fixture().id
               })

      assert message.body == "Fridge 2 is fixed"
      assert message.author_id == scope.team_member.id
      assert message.conversation_id == channel.id
      assert message.author.name == scope.team_member.name
    end

    test "rejects a blank or overlong message", %{scope: scope, channel: channel} do
      assert {:error, changeset} = Chat.send_message(scope, channel, %{body: "  "})
      assert %{body: ["can't be blank"]} = errors_on(changeset)

      assert {:error, changeset} =
               Chat.send_message(scope, channel, %{body: String.duplicate("a", 4001)})

      assert %{body: [_too_long]} = errors_on(changeset)
    end

    test "broadcasts the new message to the conversation's subscribers", %{
      scope: scope,
      channel: channel
    } do
      Chat.subscribe(scope, channel)

      {:ok, message} = Chat.send_message(scope, channel, %{body: "Doors in 10"})

      assert_receive {:message_created, %Message{id: id}}
      assert id == message.id
    end

    test "can't send to another company's conversation", %{scope: scope} do
      channel = channel_fixture()

      assert_raise Ecto.NoResultsError, fn ->
        Chat.send_message(scope, channel, %{body: "Hi"})
      end

      assert Repo.aggregate(Message, :count) == 0
    end

    test "can't send to a channel outside your audience", %{
      company: company,
      brighton: brighton,
      scope: scope
    } do
      channel = channel_fixture(company: company, site_id: brighton.id)

      assert_raise Ecto.NoResultsError, fn ->
        Chat.send_message(scope, channel, %{body: "Hi"})
      end

      assert Repo.aggregate(Message, :count) == 0
    end

    test "only reaches subscribers of that conversation", %{
      company: company,
      scope: scope,
      channel: channel
    } do
      other_channel = channel_fixture(company: company)
      Chat.subscribe(scope, channel)
      Chat.subscribe(scope, other_channel)

      {:ok, _} = Chat.send_message(scope, channel, %{body: "Just here"})

      channel_id = channel.id
      other_channel_id = other_channel.id
      assert_receive {:message_created, %Message{conversation_id: ^channel_id}}
      refute_received {:message_created, %Message{conversation_id: ^other_channel_id}}
    end
  end

  describe "list_messages/3" do
    setup %{company: company} do
      %{channel: channel_fixture(company: company)}
    end

    test "returns the latest page, oldest first, with authors", %{scope: scope, channel: channel} do
      [first, second, third] =
        for body <- ["one", "two", "three"], do: message_fixture(scope, channel, body: body)

      assert ids(Chat.list_messages(scope, channel, limit: 2)) == [second.id, third.id]
      assert ids(Chat.list_messages(scope, channel, before: second.id, limit: 2)) == [first.id]

      assert [%Message{author: %{name: name}} | _] = Chat.list_messages(scope, channel)
      assert name == scope.team_member.name
    end

    test "returns nothing from a conversation outside your audience", %{
      company: company,
      brighton: brighton,
      scope: scope
    } do
      brighton_channel = channel_fixture(company: company, site_id: brighton.id)
      brighton_scope = company_scope_fixture(team_member_fixture(site: brighton))
      message_fixture(brighton_scope, brighton_channel)

      assert Chat.list_messages(scope, brighton_channel) == []
    end
  end

  defp ids(messages), do: Enum.map(messages, & &1.id)
end
