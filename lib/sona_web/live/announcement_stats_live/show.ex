defmodule SonaWeb.AnnouncementStatsLive.Show do
  use SonaWeb, :live_view

  alias Sona.Feed
  alias Sona.Feed.Delivery

  on_mount {SonaWeb.UserAuth, :require_manager}

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope} back={~p"/announcements/stats"}>
      <:title>Announcement stats</:title>

      <div class="space-y-6">
        <article class="space-y-3 rounded-box border border-base-300 p-4">
          <header class="flex items-center gap-3">
            <.avatar name={@post.author.name} class="size-10 text-sm" />
            <div class="min-w-0 flex-1">
              <p class="truncate font-semibold">{@post.author.name}</p>
              <p class="truncate text-xs text-base-content/70">
                {audience_label(@post)} ·
                <.local_time id="post-time" at={@post.inserted_at} relative />
              </p>
            </div>
          </header>
          <div class="space-y-1">
            <h2 class="break-words text-lg font-semibold leading-snug">{@post.title}</h2>
            <p class="whitespace-pre-wrap break-words text-base-content/90">{@post.body}</p>
          </div>
        </article>

        <.stats_summary id={"stats-#{@post.id}"} stats={@stats} />

        <.group id="not-seen" title="Not seen yet" deliveries={@groups.not_seen} />
        <.group
          id="seen"
          title="Seen, not acknowledged"
          deliveries={@groups.seen}
          at={& &1.seen_at}
        />
        <.group
          id="acknowledged"
          title="Acknowledged"
          deliveries={@groups.acknowledged}
          at={& &1.acknowledged_at}
          mark_leavers
        />
        <.group
          id="left"
          title="Left without acknowledging"
          deliveries={@groups.left}
          at={& &1.team_member.left_at}
        />
      </div>
    </Layouts.app>
    """
  end

  attr :id, :string, required: true
  attr :title, :string, required: true
  attr :deliveries, :list, required: true
  attr :at, :any, default: nil, doc: "a function giving each person's time, if the group has one"
  attr :mark_leavers, :boolean, default: false, doc: "tag people who have left since"

  defp group(assigns) do
    ~H"""
    <section id={@id} aria-labelledby={"#{@id}-heading"} class="space-y-2">
      <h2
        id={"#{@id}-heading"}
        class="flex items-baseline justify-between gap-2 text-sm font-semibold uppercase tracking-wide text-base-content/70"
      >
        {@title} <span class="tabular-nums">{length(@deliveries)}</span>
      </h2>
      <p :if={@deliveries == []} class="text-sm text-base-content/60">Nobody</p>
      <ul
        :if={@deliveries != []}
        class="divide-y divide-base-200 rounded-box border border-base-300"
      >
        <li
          :for={delivery <- @deliveries}
          id={"team-member-#{delivery.team_member.id}"}
          class="flex items-center gap-3 px-3 py-2"
        >
          <.avatar name={delivery.team_member.name} class="size-8 text-xs" />
          <div class="min-w-0 flex-1">
            <p class="truncate text-sm font-medium">{delivery.team_member.name}</p>
            <p class="truncate text-xs text-base-content/70">
              {delivery.team_member.site.name} · {Phoenix.Naming.humanize(
                delivery.team_member.department
              )}
            </p>
          </div>
          <span
            :if={@mark_leavers && delivery.team_member.left_at}
            class="rounded-full bg-base-200 px-2 py-0.5 text-xs font-medium text-base-content/70"
          >
            Left
          </span>
          <.local_time
            :if={@at}
            id={"#{@id}-#{delivery.team_member.id}-time"}
            at={@at.(delivery)}
            relative
            class="shrink-0 text-xs text-base-content/70"
          />
        </li>
      </ul>
    </section>
    """
  end

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    scope = socket.assigns.current_scope
    if connected?(socket), do: Feed.subscribe_to_stats(scope)

    {:ok, assign_stats(socket, Feed.get_announcement_stats!(scope, id))}
  end

  # Changes to other announcements don't concern this page.
  @impl true
  def handle_info({:announcement_stats_changed, post_id}, socket) do
    if post_id == socket.assigns.post.id do
      {:noreply,
       assign_stats(socket, Feed.get_announcement_stats!(socket.assigns.current_scope, post_id))}
    else
      {:noreply, socket}
    end
  end

  defp assign_stats(socket, stats) do
    groups =
      Map.merge(
        %{not_seen: [], seen: [], acknowledged: [], left: []},
        socket.assigns.current_scope
        |> Feed.list_deliveries(stats.post)
        |> Enum.group_by(&Delivery.status/1)
      )

    assign(socket,
      page_title: stats.post.title,
      post: stats.post,
      stats: stats,
      groups: groups
    )
  end
end
