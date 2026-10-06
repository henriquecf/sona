defmodule SonaWeb.NoTeamLive do
  @moduledoc """
  Where a signed-in user lands without an active team member: someone who
  registered without being added to a team, or who has left (D-003).
  """
  use SonaWeb, :live_view

  alias Sona.Accounts.Scope
  alias Sona.Companies.TeamMember

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <section id="no-team" class="mx-auto max-w-sm space-y-3 text-center">
        <h1 class="text-2xl font-semibold">You're not on a team yet</h1>
        <p class="text-base-content/70">
          Ask your manager to add you to your team on Sona. Once they have, reload this page and you'll go straight to your team.
        </p>
        <.link href={~p"/users/log-out"} method="delete" class="underline">Log out</.link>
      </section>
    </Layouts.app>
    """
  end

  @impl true
  def mount(_params, _session, socket) do
    case socket.assigns.current_scope do
      %Scope{team_member: %TeamMember{}} -> {:ok, redirect(socket, to: ~p"/")}
      _ -> {:ok, socket}
    end
  end
end
