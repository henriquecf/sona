defmodule Sona.Chat do
  @moduledoc """
  Conversations and the messages in them.

  A team member sees the channels whose audience includes them, and the
  direct conversations they are one of the two people in (D-004). Reads
  and writes of existing conversations go through `visible_conversations/1`;
  starting a direct conversation is authorized by `Companies.get_colleague/2`.
  Messages are ordered and paginated by id, because timestamps only have
  second precision.
  """

  import Ecto.Query, warn: false

  alias Sona.Accounts.Scope
  alias Sona.Chat.{Conversation, Message, ReadMarker}
  alias Sona.Companies
  alias Sona.Companies.{Audience, Company, TeamMember}
  alias Sona.Repo

  @messages_per_page 50

  @doc """
  Creates a channel for an audience in `company`.

  Channels come from seeds for now (D-004), so this is a provisioning
  operation without a scope, like those in `Sona.Companies`.
  """
  def create_channel(%Company{} = company, attrs) do
    %Conversation{company_id: company.id}
    |> Conversation.channel_changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Finds or starts the direct conversation between the scope's team member
  and a colleague (an active team member of the same company).

  Returns `{:error, :not_found}` for anyone else, including yourself. The
  conversation stays out of both chats lists until it has a message.
  """
  def start_direct_conversation(%Scope{team_member: %TeamMember{} = me} = scope, colleague_id) do
    case Companies.get_colleague(scope, colleague_id) do
      nil ->
        {:error, :not_found}

      colleague ->
        {a, b} = Enum.min_max([me.id, colleague.id])

        %Conversation{company_id: me.company_id}
        |> Conversation.direct_changeset(a, b)
        |> Repo.insert!(
          on_conflict: :nothing,
          conflict_target:
            {:unsafe_fragment, "(team_member_a_id, team_member_b_id) WHERE kind = 'direct'"}
        )

        {:ok,
         Repo.one!(
           from c in Conversation,
             where: c.kind == :direct and c.team_member_a_id == ^a and c.team_member_b_id == ^b
         )}
    end
  end

  @doc """
  Returns the conversations visible to the scope's team member, most
  recently active first, each with its latest message (and author) in
  `last_message` and how many colleagues' messages the team member hasn't
  read in `unread_count`. Direct conversations without a message are left
  out.
  """
  def list_conversations(%Scope{team_member: %TeamMember{} = team_member}) do
    conversations =
      Repo.all(
        from c in visible_conversations(team_member),
          left_join: s in assoc(c, :site),
          left_join: a in assoc(c, :team_member_a),
          left_join: b in assoc(c, :team_member_b),
          preload: [site: s, team_member_a: a, team_member_b: b]
      )

    ids = Enum.map(conversations, & &1.id)
    last_messages = latest_messages(ids)
    unread_counts = unread_counts(team_member, ids)

    conversations
    |> Enum.map(
      &%{&1 | last_message: last_messages[&1.id], unread_count: Map.get(unread_counts, &1.id, 0)}
    )
    |> Enum.reject(&(&1.kind == :direct and is_nil(&1.last_message)))
    |> Enum.sort_by(&recency/1)
  end

  # The latest message of each conversation, with its author, in one query.
  # A lateral LIMIT 1 per conversation reads one index entry each, where
  # DISTINCT ON would read and sort every message in every conversation.
  defp latest_messages(conversation_ids) do
    latest =
      from m in Message,
        where: m.conversation_id == parent_as(:conversation).id,
        order_by: [desc: m.id],
        limit: 1,
        select: %{id: m.id}

    latest_ids =
      from c in Conversation,
        as: :conversation,
        where: c.id in ^conversation_ids,
        inner_lateral_join: l in subquery(latest),
        on: true,
        select: l.id

    Repo.all(
      from m in Message,
        join: a in assoc(m, :author),
        where: m.id in subquery(latest_ids),
        preload: [author: a]
    )
    |> Map.new(&{&1.conversation_id, &1})
  end

  # Colleagues' messages after the team member's read marker. Without a
  # marker, only those since they joined count (D-004), so a new starter
  # isn't greeted by a channel's whole history as unread.
  defp unread_counts(%TeamMember{} = team_member, conversation_ids) do
    # Counted per conversation through a lateral subquery, so each count is
    # an index range scan on messages (conversation_id, id) past the marker.
    unread =
      from m in Message,
        where: m.conversation_id == parent_as(:conversation).id,
        where: m.author_id != ^team_member.id,
        where: m.id > coalesce(parent_as(:marker).last_read_message_id, 0),
        where: not is_nil(parent_as(:marker).id) or m.inserted_at >= ^team_member.inserted_at,
        select: %{count: count()}

    Repo.all(
      from c in Conversation,
        as: :conversation,
        left_join: r in ReadMarker,
        as: :marker,
        on: r.conversation_id == c.id and r.team_member_id == ^team_member.id,
        where: c.id in ^conversation_ids,
        inner_lateral_join: u in subquery(unread),
        on: true,
        where: u.count > 0,
        select: {c.id, u.count}
    )
    |> Map.new()
  end

  defp recency(%Conversation{last_message: nil, name: name}), do: {1, 0, name}
  defp recency(%Conversation{last_message: message, name: name}), do: {0, -message.id, name}

  @doc """
  Gets a conversation visible to the scope's team member, with a direct
  conversation's two team members.

  Raises `Ecto.NoResultsError` for any other id, including conversations
  in other companies, outside the team member's audience, or between
  other people.
  """
  def get_conversation!(%Scope{team_member: %TeamMember{} = team_member}, id) do
    Repo.get!(
      from(c in visible_conversations(team_member),
        left_join: a in assoc(c, :team_member_a),
        left_join: b in assoc(c, :team_member_b),
        preload: [team_member_a: a, team_member_b: b]
      ),
      id
    )
  end

  @doc """
  What the scope's team member calls a conversation: a channel's name, or
  the other person's name in a direct conversation. Needs the direct
  conversation's team members loaded.
  """
  def conversation_name(_scope, %Conversation{kind: :channel, name: name}), do: name

  def conversation_name(%Scope{} = scope, %Conversation{kind: :direct} = conversation) do
    other_team_member(scope, conversation).name
  end

  @doc """
  The other person in a direct conversation the scope's team member is
  in, or `nil` for a channel. Needs the conversation's team members loaded;
  anything else raises `FunctionClauseError`.
  """
  def other_team_member(_scope, %Conversation{kind: :channel}), do: nil

  def other_team_member(%Scope{team_member: %TeamMember{id: id}}, %Conversation{
        team_member_a: %TeamMember{id: id},
        team_member_b: %TeamMember{} = other
      }),
      do: other

  def other_team_member(%Scope{team_member: %TeamMember{id: id}}, %Conversation{
        team_member_a: %TeamMember{} = other,
        team_member_b: %TeamMember{id: id}
      }),
      do: other

  @doc """
  Returns a page of the conversation's messages, oldest first, with their
  authors.

  ## Options

    * `:before` - only messages with an id lower than this, for loading
      older history.
    * `:limit` - the page size. Defaults to #{@messages_per_page}.
  """
  def list_messages(
        %Scope{team_member: %TeamMember{} = team_member},
        %Conversation{} = conversation,
        opts \\ []
      ) do
    limit = Keyword.get(opts, :limit, @messages_per_page)

    query =
      from m in Message,
        join: c in subquery(visible_conversations(team_member)),
        on: c.id == m.conversation_id,
        join: a in assoc(m, :author),
        where: m.conversation_id == ^conversation.id,
        order_by: [desc: m.id],
        limit: ^limit,
        preload: [author: a]

    query
    |> before(opts[:before])
    |> Repo.all()
    |> Enum.reverse()
  end

  defp before(query, nil), do: query
  defp before(query, id), do: where(query, [m], m.id < ^id)

  @doc """
  The default page size for `list_messages/3`.
  """
  def messages_per_page, do: @messages_per_page

  def change_message(%Message{} = message \\ %Message{}, attrs \\ %{}) do
    Message.changeset(message, attrs)
  end

  @doc """
  Posts a message as the scope's team member and broadcasts it as
  `{:message_created, message}`: on `conversation:<id>`, and for a direct
  message also on both people's `team_member:<id>` topics (D-006).

  The conversation is looked up again through the scope, so writing is
  held to the same rule as reading: raises `Ecto.NoResultsError` for a
  conversation the team member can't see. Returns
  `{:error, :recipient_left}` for a direct conversation with someone who
  has left.
  """
  def send_message(%Scope{team_member: %TeamMember{} = team_member} = scope, conversation, attrs) do
    conversation = get_conversation!(scope, conversation.id)
    recipient = other_team_member(scope, conversation)

    if recipient && recipient.left_at do
      {:error, :recipient_left}
    else
      %Message{conversation_id: conversation.id, author_id: team_member.id}
      |> Message.changeset(attrs)
      |> Repo.insert()
      |> case do
        {:ok, message} ->
          message = %{message | author: team_member}
          broadcast_created(conversation, [team_member, recipient], message)
          {:ok, message}

        {:error, changeset} ->
          {:error, changeset}
      end
    end
  end

  @doc """
  Records that the scope's team member has read their conversation up to
  `message`. The marker only moves forward, so a late or repeated call
  can't make read messages unread again.

  The conversation is looked up through the scope: raises
  `Ecto.NoResultsError` for a message in a conversation the team member
  can't see.
  """
  def mark_read(%Scope{team_member: %TeamMember{} = team_member} = scope, %Message{} = message) do
    conversation = get_conversation!(scope, message.conversation_id)

    Repo.insert!(
      %ReadMarker{
        conversation_id: conversation.id,
        team_member_id: team_member.id,
        last_read_message_id: message.id
      },
      on_conflict:
        from(r in ReadMarker,
          update: [
            set: [
              last_read_message_id:
                fragment("GREATEST(?, EXCLUDED.last_read_message_id)", r.last_read_message_id),
              updated_at: fragment("EXCLUDED.updated_at")
            ]
          ]
        ),
      conflict_target: [:team_member_id, :conversation_id]
    )

    :ok
  end

  @doc """
  Subscribes the caller to new messages in a conversation it fetched
  through the same scope (D-006).
  """
  def subscribe(
        %Scope{team_member: %TeamMember{company_id: company_id}},
        %Conversation{company_id: company_id} = conversation
      ) do
    Phoenix.PubSub.subscribe(Sona.PubSub, topic(conversation))
  end

  @doc """
  Subscribes the caller to its own team member's topic, which carries
  every direct message they send or receive (D-006).
  """
  def subscribe(%Scope{team_member: %TeamMember{} = team_member}) do
    Phoenix.PubSub.subscribe(Sona.PubSub, topic(team_member))
  end

  @doc """
  Subscribes a chats list to everything that can change it: the team
  member's own topic (direct messages, including new conversations) and
  every channel visible to them. Call it before listing, so nothing slips
  in between. The set of channels only changes on a transfer, which
  disconnects the session (D-003).
  """
  def subscribe_to_chats(%Scope{team_member: %TeamMember{} = team_member} = scope) do
    subscribe(scope)

    channel_ids =
      Repo.all(
        from c in visible_conversations(team_member), where: c.kind == :channel, select: c.id
      )

    Enum.each(channel_ids, &Phoenix.PubSub.subscribe(Sona.PubSub, "conversation:#{&1}"))
  end

  # Every message goes to its conversation's topic (an open conversation, and
  # chats lists for channels). A direct message also goes to both people's own
  # topics, which reach their chats lists in every tab.
  defp broadcast_created(%Conversation{kind: :channel} = conversation, _people, message) do
    Phoenix.PubSub.broadcast(Sona.PubSub, topic(conversation), {:message_created, message})
  end

  defp broadcast_created(%Conversation{kind: :direct} = conversation, people, message) do
    for target <- [conversation | people] do
      Phoenix.PubSub.broadcast(Sona.PubSub, topic(target), {:message_created, message})
    end
  end

  defp topic(%Conversation{id: id}), do: "conversation:#{id}"
  defp topic(%TeamMember{id: id}), do: "team_member:#{id}"

  defp visible_conversations(%TeamMember{} = team_member) do
    channel = dynamic([c], c.kind == :channel and ^Audience.includes(team_member))

    direct =
      dynamic(
        [c],
        c.kind == :direct and
          (c.team_member_a_id == ^team_member.id or c.team_member_b_id == ^team_member.id)
      )

    from c in Conversation,
      where: c.company_id == ^team_member.company_id,
      where: ^dynamic([c], ^channel or ^direct)
  end
end
