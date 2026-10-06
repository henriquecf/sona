defmodule Sona.Chat do
  @moduledoc """
  Conversations and the messages in them.

  A team member sees the channels whose audience includes them (D-004).
  Every read goes through `visible_conversations/1`, and messages are
  ordered and paginated by id, because timestamps only have second
  precision.
  """

  import Ecto.Query, warn: false

  alias Sona.Accounts.Scope
  alias Sona.Chat.{Conversation, Message}
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
  Returns the conversations visible to the scope's team member, by name,
  with each channel's site.
  """
  def list_conversations(%Scope{team_member: %TeamMember{} = team_member}) do
    Repo.all(
      from c in visible_conversations(team_member),
        left_join: s in assoc(c, :site),
        order_by: c.name,
        preload: [site: s]
    )
  end

  @doc """
  Gets a conversation visible to the scope's team member.

  Raises `Ecto.NoResultsError` for any other id, including conversations
  in other companies or outside the team member's audience.
  """
  def get_conversation!(%Scope{team_member: %TeamMember{} = team_member}, id) do
    Repo.get!(visible_conversations(team_member), id)
  end

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
  Posts a message as the scope's team member and broadcasts it to the
  conversation's subscribers as `{:message_created, message}`.

  The conversation is looked up again through the scope, so writing is
  held to the same rule as reading: raises `Ecto.NoResultsError` for a
  conversation the team member can't see.
  """
  def send_message(%Scope{team_member: %TeamMember{} = team_member} = scope, conversation, attrs) do
    conversation = get_conversation!(scope, conversation.id)

    %Message{conversation_id: conversation.id, author_id: team_member.id}
    |> Message.changeset(attrs)
    |> Repo.insert()
    |> case do
      {:ok, message} ->
        message = %{message | author: team_member}
        broadcast(conversation, {:message_created, message})
        {:ok, message}

      {:error, changeset} ->
        {:error, changeset}
    end
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

  defp broadcast(conversation, event) do
    Phoenix.PubSub.broadcast(Sona.PubSub, topic(conversation), event)
  end

  defp topic(%Conversation{id: id}), do: "conversation:#{id}"

  defp visible_conversations(%TeamMember{} = team_member) do
    from c in Conversation,
      where: c.kind == :channel,
      where: ^Audience.includes(team_member)
  end
end
