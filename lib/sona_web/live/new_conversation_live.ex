defmodule SonaWeb.NewConversationLive do
  use SonaWeb, :live_view

  alias Sona.{Chat, Companies}

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope} back={~p"/chats"}>
      <:title>New message</:title>

      <ul id="colleagues" phx-update="stream" class="-mx-4 divide-y divide-base-300">
        <li
          id="colleagues-empty"
          class="hidden px-4 py-12 text-center text-base-content/70 only:block"
        >
          Nobody else is on your team yet.
        </li>
        <li :for={{id, colleague} <- @streams.colleagues} id={id}>
          <button
            type="button"
            phx-click="start"
            phx-value-id={colleague.id}
            class="flex min-h-16 w-full items-center gap-3 px-4 py-3 text-left transition hover:bg-base-200 active:bg-base-300"
          >
            <.avatar name={colleague.name} class="size-11 text-sm" />
            <span class="min-w-0">
              <span class="block truncate font-semibold">{colleague.name}</span>
              <span class="block truncate text-sm text-base-content/70">
                {colleague.site.name} · {Phoenix.Naming.humanize(colleague.department)}
              </span>
            </span>
          </button>
        </li>
      </ul>
    </Layouts.app>
    """
  end

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, "New message")
     |> stream(:colleagues, Companies.list_colleagues(socket.assigns.current_scope))}
  end

  # The id comes from the client, so Chat resolves it through the scope.
  @impl true
  def handle_event("start", %{"id" => colleague_id}, socket) do
    case Chat.start_direct_conversation(socket.assigns.current_scope, colleague_id) do
      {:ok, conversation} ->
        {:noreply, push_navigate(socket, to: ~p"/chats/#{conversation}")}

      {:error, :not_found} ->
        {:noreply, put_flash(socket, :error, "That colleague isn't available.")}
    end
  end
end
