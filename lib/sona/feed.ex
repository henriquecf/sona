defmodule Sona.Feed do
  @moduledoc """
  The feed: announcements from managers to an audience, which each person
  in it acknowledges.

  A team member sees the posts whose audience includes them, plus their
  own (D-004). An announcement from someone else that they haven't
  acknowledged, posted since they joined, "needs their attention"; every
  other visible post is in their feed. Posts are ordered by id, because
  timestamps only have second precision.
  """

  import Ecto.Query, warn: false

  alias Sona.Accounts.Scope
  alias Sona.Companies.{Audience, TeamMember}
  alias Sona.Feed.{Acknowledgement, Post}
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
  manager, and broadcasts it as `{:post_created, post}` on its audience's
  topic (D-006).

  Returns `{:error, :unauthorized}` for anyone who isn't a manager.
  """
  def create_announcement(%Scope{team_member: %TeamMember{role: :manager} = author}, attrs) do
    %Post{company_id: author.company_id, author_id: author.id}
    |> Post.announcement_changeset(attrs)
    |> Repo.insert()
    |> case do
      {:ok, post} ->
        post = %{Repo.preload(post, :site) | author: author}
        Phoenix.PubSub.broadcast(Sona.PubSub, Audience.topic(post), {:post_created, post})
        {:ok, post}

      {:error, changeset} ->
        {:error, changeset}
    end
  end

  def create_announcement(%Scope{team_member: %TeamMember{}}, _attrs), do: {:error, :unauthorized}

  @doc """
  Returns the announcements that need the scope's team member's
  attention, newest first.
  """
  def list_attention(%Scope{team_member: %TeamMember{} = team_member}) do
    Repo.all(
      from [p, ack: a] in visible_posts(team_member),
        where: ^needs_attention(team_member),
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
      from [p, ack: a] in visible_posts(team_member),
        where: ^dynamic([p, ack: a], not (^needs_attention(team_member))),
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
  Records that the scope's team member has read an announcement, keeping
  the first time if they already had. Returns the post with its
  `acknowledged_at`.

  The id is looked up through the scope: raises `Ecto.NoResultsError` for
  anything but an announcement from someone else in their audience.
  """
  def acknowledge(%Scope{team_member: %TeamMember{} = team_member}, post_id) do
    post =
      Repo.one!(
        from [p, ack: a] in visible_posts(team_member),
          where: p.id == ^post_id,
          where: p.kind == :announcement and p.author_id != ^team_member.id
      )

    Repo.insert!(%Acknowledgement{post_id: post.id, team_member_id: team_member.id},
      on_conflict: :nothing,
      conflict_target: [:team_member_id, :post_id]
    )

    {:ok, Repo.one!(from [p, ack: a] in visible_posts(team_member), where: p.id == ^post.id)}
  end

  @doc """
  Subscribes the caller to new posts for the scope's team member: the four
  audience topics that include them (D-006).
  """
  def subscribe(%Scope{team_member: %TeamMember{} = team_member}) do
    Enum.each(Audience.topics(team_member), &Phoenix.PubSub.subscribe(Sona.PubSub, &1))
  end

  # Posts for the team member's audience, plus their own, with author,
  # site and when they acknowledged it (the `:ack` binding).
  defp visible_posts(%TeamMember{} = team_member) do
    from p in Post,
      join: author in assoc(p, :author),
      left_join: s in assoc(p, :site),
      left_join: a in Acknowledgement,
      as: :ack,
      on: a.post_id == p.id and a.team_member_id == ^team_member.id,
      where: p.company_id == ^team_member.company_id,
      where: ^dynamic([p], ^Audience.includes(team_member) or p.author_id == ^team_member.id),
      preload: [author: author, site: s],
      select_merge: %{acknowledged_at: a.inserted_at}
  end

  # Someone else's announcement, unacknowledged, posted since the team
  # member joined (so a new starter isn't handed the whole history).
  defp needs_attention(%TeamMember{} = team_member) do
    dynamic(
      [p, ack: a],
      p.kind == :announcement and p.author_id != ^team_member.id and is_nil(a.id) and
        p.inserted_at >= ^team_member.inserted_at
    )
  end
end
