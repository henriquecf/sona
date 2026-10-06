defmodule SonaWeb.ChatsLive do
  use SonaWeb, :live_view

  alias Sona.Chat

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope} active_tab={:chats}>
      <h1 class="sr-only">Chats</h1>
      <ul id="conversations" phx-update="stream" class="-mx-4 divide-y divide-base-300">
        <li id="conversations-empty" class="hidden px-4 py-12 text-center only:block">
          <p class="font-medium">No conversations yet</p>
          <p class="text-sm text-base-content/70">
            Your team's channels appear here as soon as your manager sets them up.
          </p>
        </li>
        <li :for={{id, conversation} <- @streams.conversations} id={id}>
          <.link
            navigate={~p"/chats/#{conversation}"}
            class="flex min-h-16 items-center gap-3 px-4 py-3 transition hover:bg-base-200 active:bg-base-300"
          >
            <span class="inline-flex size-11 shrink-0 items-center justify-center rounded-full bg-secondary text-secondary-content">
              <.icon name="hero-user-group" class="size-5" />
            </span>
            <span class="min-w-0 flex-1">
              <span class="block truncate font-semibold">{conversation.name}</span>
              <span class="block truncate text-sm text-base-content/70">
                {audience_label(conversation)}
              </span>
            </span>
          </.link>
        </li>
      </ul>
    </Layouts.app>
    """
  end

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, "Chats")
     |> stream(:conversations, Chat.list_conversations(socket.assigns.current_scope))}
  end

  defp audience_label(%{site: nil, department: nil}), do: "Everyone"
  defp audience_label(%{site: site, department: nil}), do: "Everyone at #{site.name}"

  defp audience_label(%{site: nil, department: department}),
    do: "#{department_name(department)}, every site"

  defp audience_label(%{site: site, department: department}),
    do: "#{department_name(department)} at #{site.name}"

  defp department_name(department), do: Phoenix.Naming.humanize(department)
end
