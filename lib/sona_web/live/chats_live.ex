defmodule SonaWeb.ChatsLive do
  use SonaWeb, :live_view

  alias Sona.Chat

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope} active_tab={:chats}>
      <div class="flex items-center justify-between">
        <h1 class="text-2xl font-semibold">Chats</h1>
        <.link
          id="new-conversation"
          navigate={~p"/chats/new"}
          aria-label="New message"
          class="inline-flex size-11 items-center justify-center rounded-full bg-primary text-primary-content transition hover:brightness-110 active:scale-95"
        >
          <.icon name="hero-pencil-square" class="size-5" />
        </.link>
      </div>

      <ul id="conversations" phx-update="stream" class="-mx-4 mt-2 divide-y divide-base-300">
        <li id="conversations-empty" class="hidden px-4 py-12 text-center only:block">
          <p class="font-medium">No conversations yet</p>
          <p class="text-sm text-base-content/70">
            Your team's channels appear here once they're set up. Tap the pencil to message a colleague.
          </p>
        </li>
        <li :for={{id, conversation} <- @streams.conversations} id={id}>
          <.link
            navigate={~p"/chats/#{conversation}"}
            class="flex min-h-16 items-center gap-3 px-4 py-3 transition hover:bg-base-200 active:bg-base-300"
          >
            <.conversation_avatar conversation={conversation} scope={@current_scope} />
            <span class="min-w-0 flex-1">
              <span class="flex items-baseline justify-between gap-2">
                <span class="truncate font-semibold">
                  {Chat.conversation_name(@current_scope, conversation)}
                </span>
                <.local_time
                  :if={conversation.last_message}
                  id={"#{id}-time"}
                  at={conversation.last_message.inserted_at}
                  relative
                  class="shrink-0 text-xs text-base-content/60"
                />
              </span>
              <span class="block truncate text-sm text-base-content/70">
                {preview(conversation, @current_scope)}
              </span>
            </span>
          </.link>
        </li>
      </ul>
    </Layouts.app>
    """
  end

  attr :conversation, :map, required: true
  attr :scope, :map, required: true

  defp conversation_avatar(%{conversation: %{kind: :direct}} = assigns) do
    ~H"""
    <.avatar name={Chat.conversation_name(@scope, @conversation)} class="size-11 text-sm" />
    """
  end

  defp conversation_avatar(assigns) do
    ~H"""
    <span class="inline-flex size-11 shrink-0 items-center justify-center rounded-full bg-secondary text-secondary-content">
      <.icon name="hero-user-group" class="size-5" />
    </span>
    """
  end

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket), do: Chat.subscribe_to_chats(socket.assigns.current_scope)

    {:ok,
     socket
     |> assign(:page_title, "Chats")
     |> load_conversations()}
  end

  # Any new message can reorder the list or add a direct conversation, so
  # reload it (two queries): a team member has a handful of conversations.
  @impl true
  def handle_info({:message_created, _message}, socket) do
    {:noreply, load_conversations(socket)}
  end

  defp load_conversations(socket) do
    conversations = Chat.list_conversations(socket.assigns.current_scope)
    stream(socket, :conversations, conversations, reset: true)
  end

  defp preview(%{last_message: nil} = conversation, _scope), do: audience_label(conversation)

  defp preview(%{last_message: message, kind: kind}, scope) do
    cond do
      message.author_id == scope.team_member.id -> "You: #{message.body}"
      kind == :channel -> "#{first_name(message.author.name)}: #{message.body}"
      true -> message.body
    end
  end

  defp first_name(name), do: name |> String.split() |> hd()

  defp audience_label(%{site: nil, department: nil}), do: "Everyone"
  defp audience_label(%{site: site, department: nil}), do: "Everyone at #{site.name}"

  defp audience_label(%{site: nil, department: department}),
    do: "#{department_name(department)}, every site"

  defp audience_label(%{site: site, department: department}),
    do: "#{department_name(department)} at #{site.name}"

  defp department_name(department), do: Phoenix.Naming.humanize(department)
end
