defmodule SonaWeb.ChatsLive do
  use SonaWeb, :live_view

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope} active_tab={:chats}>
      <section id="chats">
        <h1 class="text-2xl font-semibold">Chats</h1>
      </section>
    </Layouts.app>
    """
  end

  @impl true
  def mount(_params, _session, socket) do
    {:ok, assign(socket, :page_title, "Chats")}
  end
end
