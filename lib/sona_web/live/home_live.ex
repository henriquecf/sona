defmodule SonaWeb.HomeLive do
  use SonaWeb, :live_view

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope} active_tab={:home}>
      <section id="home">
        <h1 id="home-greeting" class="text-2xl font-semibold">
          Hi, {@current_scope.team_member.name}
        </h1>
      </section>
    </Layouts.app>
    """
  end

  @impl true
  def mount(_params, _session, socket) do
    {:ok, assign(socket, :page_title, "Home")}
  end
end
