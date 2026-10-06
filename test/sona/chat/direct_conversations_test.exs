defmodule Sona.Chat.DirectConversationsTest do
  use Sona.DataCase, async: true

  import Sona.ChatFixtures
  import Sona.CompaniesFixtures

  alias Sona.Chat
  alias Sona.Chat.Conversation
  alias Sona.Companies

  setup do
    company = company_fixture()
    me = team_member_fixture(site: site_fixture(company: company), name: "Ana Costa")

    colleague =
      team_member_fixture(site: site_fixture(company: company), name: "Kwame Mensah")

    %{
      me: company_scope_fixture(me),
      colleague: company_scope_fixture(colleague)
    }
  end

  describe "start_direct_conversation/2" do
    test "starts one conversation per pair, whoever starts it", %{me: me, colleague: colleague} do
      assert {:ok, conversation} = Chat.start_direct_conversation(me, colleague.team_member.id)
      assert conversation.kind == :direct

      assert {:ok, ^conversation} = Chat.start_direct_conversation(me, colleague.team_member.id)

      assert {:ok, ^conversation} =
               Chat.start_direct_conversation(colleague, "#{me.team_member.id}")
    end

    test "refuses yourself, another company's team member and someone who has left", %{me: me} do
      other_company_member = team_member_fixture()
      leaver = team_member_fixture(site: me.team_member.site)
      {:ok, _} = Companies.offboard_team_member(leaver, DateTime.utc_now(:second))

      assert {:error, :not_found} = Chat.start_direct_conversation(me, me.team_member.id)
      assert {:error, :not_found} = Chat.start_direct_conversation(me, other_company_member.id)
      assert {:error, :not_found} = Chat.start_direct_conversation(me, leaver.id)
    end
  end

  describe "the database" do
    test "rejects a conversation with yourself", %{me: me} do
      id = me.team_member.id

      assert {:error, changeset} =
               %Conversation{company_id: me.team_member.company_id}
               |> Conversation.direct_changeset(id, id)
               |> Repo.insert()

      assert %{team_member_b_id: ["is invalid"]} = errors_on(changeset)
    end

    test "rejects a pair across companies", %{me: me} do
      stranger = team_member_fixture()
      {a, b} = Enum.min_max([me.team_member.id, stranger.id])

      assert {:error, changeset} =
               %Conversation{company_id: me.team_member.company_id}
               |> Conversation.direct_changeset(a, b)
               |> Repo.insert()

      assert %{team_member_b_id: ["does not exist"]} = errors_on(changeset)
    end

    test "rejects a second conversation for the same pair", %{me: me, colleague: colleague} do
      {a, b} = Enum.min_max([me.team_member.id, colleague.team_member.id])

      insert = fn ->
        %Conversation{company_id: me.team_member.company_id}
        |> Conversation.direct_changeset(a, b)
        |> Repo.insert()
      end

      assert {:ok, _} = insert.()
      assert {:error, changeset} = insert.()
      assert %{team_member_a_id: ["has already been taken"]} = errors_on(changeset)
    end
  end

  describe "visibility" do
    setup %{me: me, colleague: colleague} do
      {:ok, conversation} = Chat.start_direct_conversation(me, colleague.team_member.id)
      %{conversation: conversation}
    end

    test "both people can open it, nobody else can", %{
      me: me,
      colleague: colleague,
      conversation: conversation
    } do
      bystander = company_scope_fixture(team_member_fixture(site: me.team_member.site))

      assert Chat.get_conversation!(me, conversation.id).id == conversation.id
      assert Chat.get_conversation!(colleague, conversation.id).id == conversation.id

      assert_raise Ecto.NoResultsError, fn ->
        Chat.get_conversation!(bystander, conversation.id)
      end
    end

    test "it is listed once it has a message, named after the other person", %{
      me: me,
      colleague: colleague,
      conversation: conversation
    } do
      refute Enum.any?(Chat.list_conversations(me), &(&1.id == conversation.id))

      message_fixture(me, conversation, body: "Can you swap Saturday?")

      assert [listed] = Chat.list_conversations(colleague)
      assert listed.id == conversation.id
      assert Chat.conversation_name(colleague, listed) == "Ana Costa"
      assert Chat.conversation_name(me, hd(Chat.list_conversations(me))) == "Kwame Mensah"
    end
  end

  describe "messages" do
    setup %{me: me, colleague: colleague} do
      {:ok, conversation} = Chat.start_direct_conversation(me, colleague.team_member.id)
      %{conversation: conversation}
    end

    test "reach both people's own topics, and nobody else's", %{
      me: me,
      colleague: colleague,
      conversation: conversation
    } do
      bystander = company_scope_fixture(team_member_fixture(site: me.team_member.site))
      topics = for scope <- [me, colleague, bystander], do: "team_member:#{scope.team_member.id}"
      Enum.each(topics, &Phoenix.PubSub.subscribe(Sona.PubSub, &1))

      {:ok, message} = Chat.send_message(me, conversation, %{body: "Hi!"})

      # Two deliveries: one for each person in the conversation.
      assert_receive {:message_created, %{id: id}}
      assert_receive {:message_created, %{id: ^id}}
      assert id == message.id
      refute_receive {:message_created, _}
    end

    test "channel messages reach no one's own topic", %{me: me} do
      channel = channel_fixture(company: me.team_member.company)
      Chat.subscribe(me)

      {:ok, _} = Chat.send_message(me, channel, %{body: "Hello all"})

      refute_receive {:message_created, _}
    end

    test "can't be sent once the other person has left, but stay readable", %{
      me: me,
      colleague: colleague,
      conversation: conversation
    } do
      message_fixture(me, conversation, body: "Thanks for everything")
      {:ok, _} = Companies.offboard_team_member(colleague.team_member, DateTime.utc_now(:second))

      assert {:error, :recipient_left} =
               Chat.send_message(me, conversation, %{body: "Are you still there?"})

      assert [%{body: "Thanks for everything"}] = Chat.list_messages(me, conversation)
    end
  end
end
