defmodule Sona.Feed do
  @moduledoc """
  The feed: announcements from managers to an audience, which each person
  it was sent to acknowledges, and shout-outs, in which anyone recognises a
  colleague for living a company value, for the whole company to see.

  A team member sees the posts whose audience includes them, plus their
  own (D-004), plus the announcements sent to them (D-008). An announcement
  sent to them that they haven't acknowledged "needs their attention";
  every other visible post is in their feed. Posts are ordered by id,
  because timestamps only have second precision.
  """

  import Ecto.Query, warn: false

  alias Sona.Accounts.Scope
  alias Sona.Companies
  alias Sona.Companies.{Audience, TeamMember}
  alias Sona.Feed.{Delivery, Post}
  alias Sona.Repo

  @posts_per_page 20

  # Pending announcements past this many aren't shown until earlier ones are
  # acknowledged (docs/architecture.md, D-006 consequences).
  @attention_limit 50

  def change_announcement(%Post{} = post \\ %Post{}, attrs \\ %{}) do
    Post.announcement_changeset(post, attrs)
  end

  @doc """
  Posts an announcement from the scope's team member, who must be a
  manager, sends it to everyone in its audience apart from them (D-008),
  and broadcasts it as `{:post_created, post}` on its audience's topic
  (D-006).

  Returns `{:error, :unauthorized}` for anyone who isn't a manager.
  """
  def create_announcement(%Scope{team_member: %TeamMember{role: :manager} = author}, attrs) do
    changeset =
      Post.announcement_changeset(
        %Post{company_id: author.company_id, author_id: author.id},
        attrs
      )

    with {:ok, post} <- Repo.transact(fn -> insert_and_deliver(changeset) end) do
      post = %{Repo.preload(post, :site) | author: author}
      Phoenix.PubSub.broadcast(Sona.PubSub, Audience.topic(post), {:post_created, post})
      {:ok, post}
    end
  end

  def create_announcement(%Scope{team_member: %TeamMember{}}, _attrs), do: {:error, :unauthorized}

  # One delivery for each active team member in the audience, apart from
  # the author, in a single INSERT ... SELECT.
  defp insert_and_deliver(changeset) do
    with {:ok, post} <- Repo.insert(changeset) do
      recipients =
        from tm in Audience.members(post),
          where: tm.id != ^post.author_id,
          select: %{
            company_id: tm.company_id,
            post_id: type(^post.id, :id),
            team_member_id: tm.id
          }

      Repo.insert_all(Delivery, recipients)
      {:ok, post}
    end
  end

  def change_shout_out(%Post{} = post \\ %Post{}, attrs \\ %{}) do
    Post.shout_out_changeset(post, attrs)
  end

  @doc """
  Posts a shout-out from the scope's team member to a colleague, for one of
  the company's values, and broadcasts it as `{:post_created, post}` to the
  whole company.

  The recipient must be an active colleague (not yourself); the database
  holds the value to the same company.
  """
  def create_shout_out(%Scope{team_member: %TeamMember{} = author} = scope, attrs) do
    changeset =
      %Post{company_id: author.company_id, author_id: author.id}
      |> Post.shout_out_changeset(attrs)
      |> validate_colleague(scope)

    with {:ok, post} <- Repo.insert(changeset) do
      post =
        %{Repo.preload(post, [:site, :recipient, :company_value]) | author: author}

      Phoenix.PubSub.broadcast(Sona.PubSub, Audience.topic(post), {:post_created, post})
      {:ok, post}
    end
  end

  # The id comes from the client: only an active colleague in the company
  # can be recognised.
  defp validate_colleague(changeset, scope) do
    Ecto.Changeset.validate_change(changeset, :recipient_id, fn :recipient_id, id ->
      case Companies.get_colleague(scope, id) do
        nil -> [recipient_id: "isn't one of your colleagues"]
        _colleague -> []
      end
    end)
  end

  @doc """
  Returns the announcements that need the scope's team member's
  attention, newest first.
  """
  def list_attention(%Scope{team_member: %TeamMember{} = team_member}) do
    Repo.all(
      from [p] in visible_posts(team_member),
        where: ^needs_attention(),
        order_by: [desc: p.id],
        limit: @attention_limit
    )
  end

  @doc """
  Returns a page of the scope's team member's feed, newest first: every
  visible post that doesn't need their attention.

  ## Options

    * `:before` - only posts with an id lower than this.
    * `:limit` - the page size. Defaults to #{@posts_per_page}.
  """
  def list_feed(%Scope{team_member: %TeamMember{} = team_member}, opts \\ []) do
    query =
      from [p] in visible_posts(team_member),
        where: ^dynamic(not (^needs_attention())),
        order_by: [desc: p.id],
        limit: ^Keyword.get(opts, :limit, @posts_per_page)

    query
    |> before(opts[:before])
    |> Repo.all()
  end

  defp before(query, nil), do: query
  defp before(query, id), do: where(query, [p], p.id < ^id)

  @doc """
  The default page size for `list_feed/2`.
  """
  def posts_per_page, do: @posts_per_page

  @doc """
  Records that the scope's team member has seen these announcements,
  keeping the first time (D-008). Posts that weren't sent to them are
  ignored.
  """
  def mark_seen(%Scope{team_member: %TeamMember{}}, []), do: :ok

  def mark_seen(%Scope{team_member: %TeamMember{} = team_member}, posts) do
    Repo.update_all(
      from(d in Delivery,
        where: d.team_member_id == ^team_member.id and d.post_id in ^Enum.map(posts, & &1.id),
        where: is_nil(d.seen_at)
      ),
      set: [seen_at: DateTime.utc_now(:second)]
    )

    :ok
  end

  @doc """
  Records that the scope's team member has read an announcement, which
  also counts as seeing it, keeping the first times if they already had.
  Returns the post with its `acknowledged_at`.

  The id is looked up through the scope: raises `Ecto.NoResultsError` for
  anything but an announcement sent to them.
  """
  def acknowledge(%Scope{team_member: %TeamMember{} = team_member}, post_id) do
    delivery =
      Repo.one!(
        from d in Delivery, where: d.team_member_id == ^team_member.id and d.post_id == ^post_id
      )

    now = DateTime.utc_now(:second)

    Repo.update_all(
      from(d in Delivery,
        where: d.id == ^delivery.id and is_nil(d.acknowledged_at),
        update: [set: [acknowledged_at: ^now, seen_at: coalesce(d.seen_at, ^now)]]
      ),
      []
    )

    {:ok, Repo.one!(from [p] in visible_posts(team_member), where: p.id == ^delivery.post_id)}
  end

  @doc """
  Subscribes the caller to new posts for the scope's team member: the four
  audience topics that include them (D-006).
  """
  def subscribe(%Scope{team_member: %TeamMember{} = team_member}) do
    Enum.each(Audience.topics(team_member), &Phoenix.PubSub.subscribe(Sona.PubSub, &1))
  end

  # Posts for the team member's audience, plus their own, plus the
  # announcements sent to them, with author, site and when they
  # acknowledged it (the `:delivery` binding).
  defp visible_posts(%TeamMember{} = team_member) do
    from p in Post,
      join: author in assoc(p, :author),
      left_join: s in assoc(p, :site),
      left_join: recipient in assoc(p, :recipient),
      left_join: value in assoc(p, :company_value),
      left_join: d in Delivery,
      as: :delivery,
      on: d.post_id == p.id and d.team_member_id == ^team_member.id,
      where: p.company_id == ^team_member.company_id,
      where:
        ^dynamic(
          [p, delivery: d],
          ^Audience.includes(team_member) or p.author_id == ^team_member.id or not is_nil(d.id)
        ),
      preload: [author: author, site: s, recipient: recipient, company_value: value],
      select_merge: %{acknowledged_at: d.acknowledged_at}
  end

  # Sent to them and not yet acknowledged. A new starter has no delivery
  # for earlier announcements, so isn't handed the whole history.
  defp needs_attention do
    dynamic([delivery: d], not is_nil(d.id) and is_nil(d.acknowledged_at))
  end
end
