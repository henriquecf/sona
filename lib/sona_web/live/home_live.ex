defmodule SonaWeb.HomeLive do
  use SonaWeb, :live_view

  alias Sona.Feed
  alias Sona.Feed.Post

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope} active_tab={:home}>
      <section id="home" class="space-y-6">
        <div class="space-y-3">
          <h1 id="home-greeting" class="text-2xl font-semibold">
            Hi, {first_name(@current_scope.team_member.name)}
          </h1>
          <div class="flex flex-wrap gap-2">
            <.link
              id="new-shout-out"
              navigate={~p"/shout-outs/new"}
              class="inline-flex min-h-11 items-center gap-2 rounded-full bg-secondary px-4 text-sm font-semibold text-secondary-content transition hover:brightness-110 active:scale-95"
            >
              <.icon name="hero-sparkles" class="size-5" /> Give a shout-out
            </.link>
            <.link
              :if={@current_scope.team_member.role == :manager}
              id="new-announcement"
              navigate={~p"/announcements/new"}
              class="inline-flex min-h-11 items-center gap-2 rounded-full bg-primary px-4 text-sm font-semibold text-primary-content transition hover:brightness-110 active:scale-95"
            >
              <.icon name="hero-megaphone" class="size-5" /> Announce
            </.link>
          </div>
        </div>

        <%!-- Always rendered, so the stream stays mounted; hidden while empty. --%>
        <section aria-labelledby="attention-heading" class="hidden space-y-3 has-[li]:block">
          <h2
            id="attention-heading"
            class="flex items-center gap-2 text-sm font-semibold uppercase tracking-wide text-primary"
          >
            <.icon name="hero-bell-alert" class="size-5" /> Needs your attention
          </h2>
          <ol id="attention" phx-update="stream" class="flex flex-col gap-3">
            <li :for={{id, post} <- @streams.attention} id={id} style={"order: -#{post.id}"}>
              <.post_card post={post} id={id} highlighted>
                <:action>
                  <button
                    id={"acknowledge-#{post.id}"}
                    type="button"
                    phx-click="acknowledge"
                    phx-value-id={post.id}
                    class="inline-flex min-h-11 w-full items-center justify-center gap-2 rounded-full bg-primary px-4 font-semibold text-primary-content transition hover:brightness-110 active:scale-95 phx-click-loading:opacity-60"
                  >
                    <.icon name="hero-check" class="size-5" /> Got it
                  </button>
                </:action>
              </.post_card>
            </li>
          </ol>
        </section>

        <section aria-labelledby="feed-heading" class="space-y-3">
          <h2
            id="feed-heading"
            class="text-sm font-semibold uppercase tracking-wide text-base-content/60"
          >
            Latest
          </h2>
          <%!-- Ordered by id, newest first, whatever the insert position:
               an acknowledged announcement takes its place by date. --%>
          <ol id="feed" phx-update="stream" class="flex flex-col gap-3">
            <li
              id="feed-empty"
              class="hidden rounded-box border border-dashed border-base-300 px-4 py-10 text-center text-base-content/70 only:block"
            >
              News from across the company will appear here.
            </li>
            <li
              :for={{id, post} <- @streams.feed}
              id={id}
              style={"order: -#{post.id}"}
              data-kind={post.kind}
            >
              <.post_card post={post} id={id}>
                <:action :if={post.acknowledged_at}>
                  <p
                    data-role="acknowledged"
                    class="flex items-center gap-1.5 text-sm font-medium text-secondary"
                  >
                    <.icon name="hero-check-circle" class="size-5" /> Acknowledged
                  </p>
                </:action>
              </.post_card>
            </li>
          </ol>
          <div :if={@feed_more?} class="flex justify-center">
            <button
              id="load-more"
              type="button"
              phx-click="load-more"
              class="min-h-11 rounded-full border border-base-300 px-4 text-sm font-medium transition hover:bg-base-200 phx-click-loading:opacity-60"
            >
              Load more
            </button>
          </div>
        </section>
      </section>
    </Layouts.app>
    """
  end

  attr :post, :map, required: true
  attr :id, :string, required: true
  attr :highlighted, :boolean, default: false
  slot :action

  defp post_card(%{post: %Post{kind: :shout_out}} = assigns) do
    ~H"""
    <article class="space-y-3 rounded-box border border-secondary/30 bg-secondary/5 p-4">
      <header class="flex items-center gap-3">
        <span class="inline-flex size-10 shrink-0 items-center justify-center rounded-full bg-secondary text-secondary-content">
          <.icon name="hero-sparkles" class="size-5" />
        </span>
        <p class="min-w-0 flex-1 text-sm leading-snug">
          <span class="font-semibold">{@post.author.name}</span>
          recognised <span class="font-semibold">{@post.recipient.name}</span>
          <span class="block text-xs text-base-content/70">
            <.local_time id={"#{@id}-time"} at={@post.inserted_at} relative />
          </span>
        </p>
      </header>
      <p class="inline-flex items-center gap-1.5 rounded-full bg-secondary px-3 py-1 text-sm font-semibold text-secondary-content">
        <.icon name="hero-heart-solid" class="size-4" /> {@post.company_value.name}
      </p>
      <p class="whitespace-pre-wrap break-words text-base-content/90">{@post.body}</p>
    </article>
    """
  end

  defp post_card(assigns) do
    ~H"""
    <article class={[
      "space-y-3 rounded-box border p-4",
      if(@highlighted,
        do: "border-primary/40 bg-primary/5",
        else: "border-base-300 bg-base-100"
      )
    ]}>
      <header class="flex items-center gap-3">
        <.avatar name={@post.author.name} class="size-10 text-sm" />
        <div class="min-w-0 flex-1">
          <p class="truncate font-semibold">{@post.author.name}</p>
          <p class="truncate text-xs text-base-content/70">
            To {lowercase_first(audience_label(@post))} ·
            <.local_time id={"#{@id}-time"} at={@post.inserted_at} relative />
          </p>
        </div>
      </header>
      <div class="space-y-1">
        <h3 class="break-words text-lg font-semibold leading-snug">{@post.title}</h3>
        <p class="whitespace-pre-wrap break-words text-base-content/90">{@post.body}</p>
      </div>
      {render_slot(@action)}
    </article>
    """
  end

  # "Everyone at Soho" reads as "To everyone at Soho"; site names keep their case.
  defp lowercase_first(<<first::utf8, rest::binary>>),
    do: String.downcase(<<first::utf8>>) <> rest

  @impl true
  def mount(_params, _session, socket) do
    scope = socket.assigns.current_scope
    if connected?(socket), do: Feed.subscribe(scope)

    attention = Feed.list_attention(scope)
    feed = Feed.list_feed(scope)

    {:ok,
     socket
     |> assign(:page_title, "Home")
     |> assign_feed_page(feed)
     |> stream(:attention, attention)
     |> stream(:feed, feed)}
  end

  # The id comes from the client, so Feed resolves it through the scope.
  @impl true
  def handle_event("acknowledge", %{"id" => id}, socket) do
    {:ok, post} = Feed.acknowledge(socket.assigns.current_scope, id)

    {:noreply,
     socket
     |> stream_delete(:attention, post)
     # Shown in id order (CSS order). Inserting at 0 keeps the DOM order, which
     # screen readers follow, close: acknowledged posts are usually recent.
     |> stream_insert(:feed, post, at: 0)}
  end

  def handle_event("load-more", _params, socket) do
    older = Feed.list_feed(socket.assigns.current_scope, before: socket.assigns.oldest_feed_id)

    {:noreply,
     socket
     |> assign_feed_page(older)
     |> stream(:feed, older)}
  end

  @impl true
  # Someone else's new announcement needs attention; anything else (your own
  # post, or a shout-out) goes straight into the feed.
  def handle_info({:post_created, %Post{kind: :announcement} = post}, socket)
      when post.author_id != socket.assigns.current_scope.team_member.id do
    {:noreply, stream_insert(socket, :attention, post, at: 0)}
  end

  def handle_info({:post_created, post}, socket) do
    {:noreply, stream_insert(socket, :feed, post, at: 0)}
  end

  defp assign_feed_page(socket, []), do: assign(socket, feed_more?: false, oldest_feed_id: nil)

  defp assign_feed_page(socket, posts) do
    assign(socket,
      feed_more?: length(posts) == Feed.posts_per_page(),
      oldest_feed_id: List.last(posts).id
    )
  end
end
