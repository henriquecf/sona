defmodule SonaWeb.ConversationLive do
  use SonaWeb, :live_view

  alias Sona.Chat

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope} back={~p"/chats"}>
      <:title>{@title}</:title>

      <div class="flex flex-1 flex-col pb-20">
        <div :if={@more?} class="mb-4 flex justify-center">
          <button
            id="load-older"
            type="button"
            phx-click="load-older"
            class="min-h-11 rounded-full border border-base-300 px-4 text-sm font-medium transition hover:bg-base-200 phx-click-loading:opacity-60"
          >
            Load older messages
          </button>
        </div>

        <ol
          id="messages"
          phx-update="stream"
          phx-hook=".ScrollToLatest"
          class="mt-auto flex flex-col gap-3"
        >
          <li id="messages-empty" class="hidden py-12 text-center text-base-content/70 only:block">
            No messages yet. Say hello!
          </li>
          <li
            :for={{id, message} <- @streams.messages}
            id={id}
            data-mine={message.author_id == @current_scope.team_member.id}
            class="group flex items-end gap-2 data-mine:flex-row-reverse"
          >
            <.avatar name={message.author.name} class="size-8 text-xs group-data-mine:hidden" />
            <div class="max-w-[80%] space-y-1">
              <p
                data-role="author"
                class="px-3 text-xs font-medium text-base-content/70 group-data-mine:hidden"
              >
                {message.author.name}
              </p>
              <div class="rounded-2xl rounded-bl-md bg-base-200 px-3 py-2 group-data-mine:rounded-bl-2xl group-data-mine:rounded-br-md group-data-mine:bg-primary group-data-mine:text-primary-content">
                <p class="whitespace-pre-wrap break-words">{message.body}</p>
                <.local_time
                  id={"#{id}-time"}
                  at={message.inserted_at}
                  class="mt-0.5 block text-right text-[11px] opacity-70"
                />
              </div>
            </div>
          </li>
        </ol>
      </div>

      <div class="fixed inset-x-0 bottom-0 z-20 border-t border-base-300 bg-base-100/95 pb-[env(safe-area-inset-bottom)] backdrop-blur">
        <p
          :if={@recipient_left?}
          id="recipient-left"
          class="mx-auto max-w-lg px-4 py-4 text-center text-sm text-base-content/70"
        >
          {@title} has left, so you can read this conversation but not reply.
        </p>
        <.form
          :if={!@recipient_left?}
          for={@form}
          id="message-form"
          phx-change="validate"
          phx-submit="send"
          class="mx-auto flex max-w-lg items-center gap-2 px-3 py-2"
        >
          <input
            type="text"
            name={@form[:body].name}
            id={@form[:body].id}
            value={@form[:body].value}
            placeholder="Message"
            autocomplete="off"
            maxlength="4000"
            aria-label="Message"
            class="min-h-11 flex-1 rounded-full border border-base-300 bg-base-100 px-4 outline-none transition focus:border-primary"
          />
          <button
            type="submit"
            aria-label="Send"
            class="inline-flex size-11 shrink-0 items-center justify-center rounded-full bg-primary text-primary-content transition hover:brightness-110 active:scale-95 phx-submit-loading:opacity-60"
          >
            <.icon name="hero-paper-airplane-solid" class="size-5" />
          </button>
        </.form>
      </div>

      <script :type={Phoenix.LiveView.ColocatedHook} name=".ScrollToLatest">
        // The page scrolls, not the list. Start at the latest message, follow new
        // ones while the reader is near the bottom, and keep the reader's place
        // when older messages are added above.
        export default {
          mounted() { this.scrollToLatest() },
          beforeUpdate() {
            const page = document.documentElement
            this.fromBottom = page.scrollHeight - window.scrollY - window.innerHeight
          },
          updated() {
            const page = document.documentElement
            if (this.fromBottom < 160) {
              this.scrollToLatest()
            } else {
              window.scrollTo(0, page.scrollHeight - window.innerHeight - this.fromBottom)
            }
          },
          scrollToLatest() { window.scrollTo(0, document.documentElement.scrollHeight) }
        }
      </script>
    </Layouts.app>
    """
  end

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    scope = socket.assigns.current_scope
    conversation = Chat.get_conversation!(scope, id)

    # Subscribe before loading, so no message slips in between. A message in
    # both is inserted once: stream items are keyed by DOM id.
    if connected?(socket), do: Chat.subscribe(scope, conversation)

    messages = Chat.list_messages(scope, conversation)

    # Opening a conversation reads it. Only on the live mount: the first,
    # static render isn't someone reading.
    if connected?(socket) and messages != [], do: Chat.mark_read(scope, List.last(messages))

    title = Chat.conversation_name(scope, conversation)
    recipient = Chat.other_team_member(scope, conversation)

    {:ok,
     socket
     |> assign(:page_title, title)
     |> assign(:title, title)
     |> assign(:recipient_left?, recipient != nil and recipient.left_at != nil)
     |> assign(:conversation, conversation)
     |> assign_page(messages)
     |> assign_form(Chat.change_message())
     |> stream(:messages, messages)}
  end

  # Tracking what's typed lets the reset after sending reach the client:
  # otherwise the empty value never differs from what the server last sent.
  @impl true
  def handle_event("validate", %{"message" => params}, socket) do
    {:noreply, assign_form(socket, Chat.change_message(%Chat.Message{}, params))}
  end

  def handle_event("send", %{"message" => params}, socket) do
    %{current_scope: scope, conversation: conversation} = socket.assigns

    case Chat.send_message(scope, conversation, params) do
      {:ok, message} ->
        {:noreply,
         socket
         |> stream_insert(:messages, message)
         |> assign_form(Chat.change_message())}

      {:error, :recipient_left} ->
        {:noreply, assign(socket, :recipient_left?, true)}

      {:error, changeset} ->
        {:noreply, assign_form(socket, changeset)}
    end
  end

  def handle_event("load-older", _params, socket) do
    %{current_scope: scope, conversation: conversation, oldest_id: oldest_id} = socket.assigns
    older = Chat.list_messages(scope, conversation, before: oldest_id)

    {:noreply,
     socket
     |> assign_page(older)
     # Inserting at 0 one by one reverses the batch, so reverse it first.
     |> stream(:messages, Enum.reverse(older), at: 0)}
  end

  @impl true
  def handle_info({:message_created, message}, socket) do
    # The conversation is open, so its new messages are read as they arrive.
    Chat.mark_read(socket.assigns.current_scope, message)
    {:noreply, stream_insert(socket, :messages, message)}
  end

  # Track where the next older page starts, and whether there is one.
  defp assign_page(socket, []), do: assign(socket, more?: false, oldest_id: nil)

  defp assign_page(socket, [oldest | _] = messages) do
    assign(socket,
      more?: length(messages) == Chat.messages_per_page(),
      oldest_id: oldest.id
    )
  end

  defp assign_form(socket, changeset), do: assign(socket, :form, to_form(changeset, as: :message))
end
