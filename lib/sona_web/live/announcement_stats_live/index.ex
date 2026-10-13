defmodule SonaWeb.AnnouncementStatsLive.Index do
  use SonaWeb, :live_view

  alias Sona.Feed

  on_mount {SonaWeb.UserAuth, :require_manager}

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope} back={~p"/"}>
      <:title>Announcement stats</:title>

      <%!-- Ordered by id, newest first, whatever the insert position. --%>
      <ol id="announcements" phx-update="stream" class="flex flex-col gap-3">
        <li
          id="announcements-empty"
          class="hidden rounded-box border border-dashed border-base-300 px-4 py-10 text-center text-base-content/70 only:block"
        >
          Announcements from across the company will appear here.
        </li>
        <li
          :for={{id, stats} <- @streams.announcements}
          id={id}
          style={"order: -#{stats.post.id}"}
        >
          <.link
            navigate={~p"/announcements/#{stats.post.id}/stats"}
            class="block space-y-3 rounded-box border border-base-300 bg-base-100 p-4 transition hover:border-primary/50 active:scale-[0.99]"
          >
            <div class="space-y-1">
              <h2 class="break-words font-semibold leading-snug">{stats.post.title}</h2>
              <p class="truncate text-xs text-base-content/70">
                {audience_label(stats.post)} · {stats.post.author.name} ·
                <.local_time id={"#{id}-time"} at={stats.post.inserted_at} relative />
              </p>
            </div>
            <.stats_summary id={"stats-#{stats.post.id}"} stats={stats} />
          </.link>
        </li>
      </ol>

      <div :if={@more?} class="mt-4 flex justify-center">
        <button
          id="load-more"
          type="button"
          phx-click="load-more"
          class="min-h-11 rounded-full border border-base-300 px-4 text-sm font-medium transition hover:bg-base-200 phx-click-loading:opacity-60"
        >
          Load more
        </button>
      </div>
    </Layouts.app>
    """
  end

  @impl true
  def mount(_params, _session, socket) do
    scope = socket.assigns.current_scope
    if connected?(socket), do: Feed.subscribe_to_stats(scope)

    page = Feed.list_announcement_stats(scope)

    {:ok,
     socket
     |> assign(:page_title, "Announcement stats")
     |> stream_configure(:announcements, dom_id: &"announcements-#{&1.post.id}")
     |> assign_page(page)
     |> stream(:announcements, page)}
  end

  # Everything is loaded: a late second tap has nothing to add.
  @impl true
  def handle_event("load-more", _params, %{assigns: %{more?: false}} = socket),
    do: {:noreply, socket}

  def handle_event("load-more", _params, socket) do
    older =
      Feed.list_announcement_stats(socket.assigns.current_scope,
        before: socket.assigns.oldest_id
      )

    {:noreply,
     socket
     |> assign_page(older)
     |> stream(:announcements, older)}
  end

  # Re-read an announcement this page shows, or a new one (it goes on top).
  # Older ones aren't loaded, so their changes don't concern this page.
  @impl true
  def handle_info({:announcement_stats_changed, post_id}, socket) do
    if is_nil(socket.assigns.oldest_id) or post_id >= socket.assigns.oldest_id do
      stats = Feed.get_announcement_stats!(socket.assigns.current_scope, post_id)
      {:noreply, stream_insert(socket, :announcements, stats, at: 0)}
    else
      {:noreply, socket}
    end
  end

  # With every announcement loaded, `oldest_id` is nil: any change concerns
  # this page.
  defp assign_page(socket, page) do
    more? = length(page) == Feed.posts_per_page()
    assign(socket, more?: more?, oldest_id: if(more?, do: List.last(page).post.id))
  end
end
