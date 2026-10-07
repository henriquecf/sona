defmodule SonaWeb.Layouts do
  @moduledoc """
  This module holds layouts and related functionality
  used by your application.
  """
  use SonaWeb, :html

  alias Sona.Accounts.Scope
  alias Sona.Companies.TeamMember

  # The persona switcher only exists when dev routes are compiled (D-005).
  @dev_routes Application.compile_env(:sona, :dev_routes, false)

  # Embed all files in layouts/* within this module.
  # The default root.html.heex file contains the HTML
  # skeleton of your application, namely HTML headers
  # and other static content.
  embed_templates "layouts/*"

  @doc """
  Renders the app layout.

  A team member gets the phone-first app frame (D-007). With an
  `active_tab`, it has the company header and the bottom tab bar. Without
  one, a back bar replaces both, for pages such as a conversation or
  settings. Anyone else (signed out, or not on a team) gets a plain,
  centred layout.

  ## Examples

      <Layouts.app flash={@flash} current_scope={@current_scope} active_tab={:home}>
        <h1>Content</h1>
      </Layouts.app>

      <Layouts.app flash={@flash} current_scope={@current_scope} back={~p"/chats"}>
        <:title>Soho kitchen</:title>
        ...
      </Layouts.app>

  """
  attr :flash, :map, required: true, doc: "the map of flash messages"

  attr :current_scope, :map,
    default: nil,
    doc: "the current [scope](https://phoenix.hexdocs.pm/scopes.html)"

  attr :active_tab, :atom,
    default: nil,
    values: [nil, :home, :chats],
    doc: "the tab to highlight; without one, a back bar replaces the header and tab bar"

  attr :back, :string, default: "/", doc: "where the back bar leads"

  slot :title, doc: "the back bar's title"
  slot :inner_block, required: true

  def app(%{current_scope: %Scope{team_member: %TeamMember{}}} = assigns) do
    ~H"""
    <div class="mx-auto flex min-h-dvh w-full max-w-lg flex-col bg-base-100 sm:border-x sm:border-base-300">
      <.app_header :if={@active_tab} team_member={@current_scope.team_member} />
      <.back_bar :if={!@active_tab} back={@back} title={@title} />

      <main class={["flex flex-1 flex-col px-4 py-4", @active_tab && "pb-28"]}>
        {render_slot(@inner_block)}
      </main>

      <.tab_bar :if={@active_tab} active_tab={@active_tab} />
    </div>

    <.flash_group flash={@flash} />
    """
  end

  def app(assigns) do
    ~H"""
    <div class="mx-auto flex min-h-dvh w-full max-w-md flex-col px-4">
      <header class="flex items-center justify-between py-6">
        <.link navigate={~p"/"} class="text-2xl font-bold tracking-tight text-primary">sona</.link>
        <nav id="account-nav" class="flex items-center gap-2 text-sm">
          <%= if @current_scope do %>
            <span class="hidden text-base-content/70 sm:inline">{@current_scope.user.email}</span>
            <.link
              href={~p"/users/settings"}
              class="inline-flex min-h-11 items-center px-2 hover:underline"
            >Settings</.link>
            <.link
              href={~p"/users/log-out"}
              method="delete"
              class="inline-flex min-h-11 items-center px-2 hover:underline"
            >Log out</.link>
          <% else %>
            <.link
              href={~p"/users/log-in"}
              class="inline-flex min-h-11 items-center px-2 hover:underline"
            >Log in</.link>
          <% end %>
        </nav>
      </header>
      <main class="flex-1 pb-12">
        {render_slot(@inner_block)}
      </main>
    </div>

    <.flash_group flash={@flash} />
    """
  end

  attr :team_member, TeamMember, required: true

  defp app_header(assigns) do
    ~H"""
    <header
      id="app-header"
      class="sticky top-0 z-20 flex items-center justify-between gap-3 border-b border-base-300 bg-base-100/90 px-4 py-3 backdrop-blur"
    >
      <div class="min-w-0">
        <p class="truncate text-xs font-semibold uppercase tracking-wider text-primary">
          {@team_member.company.name}
        </p>
        <p class="truncate text-lg font-semibold leading-tight">{@team_member.site.name}</p>
      </div>
      <.account_menu team_member={@team_member} />
    </header>
    """
  end

  attr :back, :string, required: true
  attr :title, :list, required: true

  defp back_bar(assigns) do
    ~H"""
    <header
      id="back-bar"
      class="sticky top-0 z-20 flex items-center gap-2 border-b border-base-300 bg-base-100/90 px-2 py-2 backdrop-blur"
    >
      <.link
        navigate={@back}
        aria-label="Back"
        class="inline-flex size-11 items-center justify-center rounded-full transition hover:bg-base-200 active:scale-95"
      >
        <.icon name="hero-chevron-left" class="size-6" />
      </.link>
      <h1 :if={@title != []} class="min-w-0 flex-1 truncate text-lg font-semibold">
        {render_slot(@title)}
      </h1>
    </header>
    """
  end

  attr :team_member, TeamMember, required: true

  # A <details> menu works on controller-rendered pages too, with no JS.
  defp account_menu(assigns) do
    assigns = assign(assigns, :dev_routes, @dev_routes)

    ~H"""
    <details id="account-menu" phx-hook=".AccountMenu" class="group relative">
      <summary
        aria-label="Account"
        class="inline-flex size-11 cursor-pointer list-none items-center justify-center rounded-full transition active:scale-95 [&::-webkit-details-marker]:hidden"
      >
        <.avatar name={@team_member.name} />
      </summary>
      <div class="absolute right-0 z-30 mt-2 w-60 rounded-box border border-base-300 bg-base-100 p-2 shadow-xl">
        <div class="flex items-center gap-3 px-3 py-2">
          <.avatar name={@team_member.name} class="size-10 text-sm" />
          <div class="min-w-0">
            <p class="truncate font-semibold">{@team_member.name}</p>
            <p class="truncate text-sm text-base-content/70">
              {Phoenix.Naming.humanize(@team_member.department)} · {Phoenix.Naming.humanize(
                @team_member.role
              )}
            </p>
          </div>
        </div>
        <div class="my-1 border-t border-base-300"></div>
        <.link
          href={~p"/users/settings"}
          class="flex min-h-11 items-center rounded-field px-3 hover:bg-base-200"
        >
          Settings
        </.link>
        <%!-- A plain href, not ~p: the route doesn't exist in production builds. --%>
        <a
          :if={@dev_routes}
          href="/dev/personas"
          class="flex min-h-11 items-center rounded-field px-3 hover:bg-base-200"
        >
          Switch persona
        </a>
        <.link
          href={~p"/users/log-out"}
          method="delete"
          class="flex min-h-11 items-center rounded-field px-3 text-error hover:bg-base-200"
        >
          Log out
        </.link>
      </div>
    </details>
    <script :type={Phoenix.LiveView.ColocatedHook} name=".AccountMenu">
      // Close like a menu: on a tap elsewhere, or on Escape. The open state is
      // the browser's, so re-renders must leave the attribute alone.
      // pointerdown, unlike click, also fires for taps on non-interactive
      // elements in iOS Safari.
      export default {
        mounted() {
          this.js().ignoreAttributes(this.el, "open")
          this.onPointer = (e) => { if (this.el.open && !this.el.contains(e.target)) this.el.open = false }
          this.onKey = (e) => {
            if (e.key === "Escape" && this.el.open) {
              const hadFocus = this.el.contains(document.activeElement)
              this.el.open = false
              if (hadFocus) this.el.querySelector("summary").focus()
            }
          }
          document.addEventListener("pointerdown", this.onPointer)
          document.addEventListener("keydown", this.onKey)
        },
        destroyed() {
          document.removeEventListener("pointerdown", this.onPointer)
          document.removeEventListener("keydown", this.onKey)
        }
      }
    </script>
    """
  end

  attr :active_tab, :atom, required: true

  defp tab_bar(assigns) do
    ~H"""
    <nav
      id="tab-bar"
      aria-label="Main"
      class="fixed inset-x-0 bottom-0 z-20 mx-auto max-w-lg border-t border-base-300 bg-base-100/95 pb-[env(safe-area-inset-bottom)] backdrop-blur sm:border-x"
    >
      <div class="grid grid-cols-2">
        <.tab
          id="tab-home"
          navigate={~p"/"}
          icon="hero-home"
          current_icon="hero-home-solid"
          current={@active_tab == :home}
        >
          Home
        </.tab>
        <.tab
          id="tab-chats"
          navigate={~p"/chats"}
          icon="hero-chat-bubble-left-right"
          current_icon="hero-chat-bubble-left-right-solid"
          current={@active_tab == :chats}
        >
          Chats
        </.tab>
      </div>
    </nav>
    """
  end

  attr :id, :string, required: true
  attr :navigate, :string, required: true
  attr :icon, :string, required: true
  attr :current_icon, :string, required: true, doc: "written out in full so Tailwind sees it"
  attr :current, :boolean, required: true
  slot :inner_block, required: true

  defp tab(assigns) do
    ~H"""
    <.link
      id={@id}
      navigate={@navigate}
      aria-current={@current && "page"}
      class={[
        "flex flex-col items-center gap-1 py-2.5 text-xs font-medium transition active:scale-95",
        if(@current, do: "text-primary", else: "text-base-content/70 hover:text-base-content")
      ]}
    >
      <.icon name={if(@current, do: @current_icon, else: @icon)} class="size-6" />
      {render_slot(@inner_block)}
    </.link>
    """
  end

  @doc """
  Shows the flash group with standard titles and content.

  ## Examples

      <.flash_group flash={@flash} />
  """
  attr :flash, :map, required: true, doc: "the map of flash messages"
  attr :id, :string, default: "flash-group", doc: "the optional id of flash container"

  def flash_group(assigns) do
    ~H"""
    <div id={@id} aria-live="polite">
      <.flash kind={:info} flash={@flash} />
      <.flash kind={:error} flash={@flash} />

      <.flash
        id="client-error"
        kind={:error}
        title={gettext("We can't find the internet")}
        phx-disconnected={
          show(".phx-client-error #client-error")
          |> JS.remove_attribute("hidden", to: ".phx-client-error #client-error")
        }
        phx-connected={hide("#client-error") |> JS.set_attribute({"hidden", ""})}
        hidden
      >
        {gettext("Attempting to reconnect")}
        <.icon name="hero-arrow-path" class="ml-1 size-3 motion-safe:animate-spin" />
      </.flash>

      <.flash
        id="server-error"
        kind={:error}
        title={gettext("Something went wrong!")}
        phx-disconnected={
          show(".phx-server-error #server-error")
          |> JS.remove_attribute("hidden", to: ".phx-server-error #server-error")
        }
        phx-connected={hide("#server-error") |> JS.set_attribute({"hidden", ""})}
        hidden
      >
        {gettext("Attempting to reconnect")}
        <.icon name="hero-arrow-path" class="ml-1 size-3 motion-safe:animate-spin" />
      </.flash>
    </div>
    """
  end
end
