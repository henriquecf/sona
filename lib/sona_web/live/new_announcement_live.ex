defmodule SonaWeb.NewAnnouncementLive do
  use SonaWeb, :live_view

  alias Sona.{Companies, Feed}
  alias Sona.Companies.TeamMember
  alias Sona.Feed.Post

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope} back={~p"/"}>
      <:title>New announcement</:title>

      <.form
        for={@form}
        id="announcement-form"
        phx-change="validate"
        phx-submit="post"
        class="space-y-1"
      >
        <.input field={@form[:title]} type="text" label="Title" maxlength="120" required />
        <.input field={@form[:body]} type="textarea" label="Message" rows="6" required />

        <fieldset class="grid grid-cols-2 gap-3">
          <legend class="mb-1 text-sm font-medium">Who is it for?</legend>
          <.input
            field={@form[:site_id]}
            type="select"
            label="Site"
            prompt="All sites"
            options={@sites}
          />
          <.input
            field={@form[:department]}
            type="select"
            label="Department"
            prompt="All departments"
            options={@departments}
          />
        </fieldset>

        <p class="pb-2 text-sm text-base-content/70">
          Everyone it's for will see it at the top of Home until they tap "Got it".
        </p>

        <button
          type="submit"
          class="inline-flex min-h-11 w-full items-center justify-center gap-2 rounded-full bg-primary px-4 font-semibold text-primary-content transition hover:brightness-110 active:scale-95 phx-submit-loading:opacity-60"
        >
          <.icon name="hero-megaphone" class="size-5" /> Post announcement
        </button>
      </.form>
    </Layouts.app>
    """
  end

  @impl true
  def mount(_params, _session, socket) do
    scope = socket.assigns.current_scope

    if scope.team_member.role == :manager do
      {:ok,
       socket
       |> assign(:page_title, "New announcement")
       |> assign(:sites, Enum.map(Companies.list_sites(scope), &{&1.name, &1.id}))
       |> assign(:departments, departments())
       |> assign(:form, to_form(Feed.change_announcement()))}
    else
      {:ok,
       socket
       |> put_flash(:error, "Only managers can post announcements.")
       |> push_navigate(to: ~p"/")}
    end
  end

  @impl true
  def handle_event("validate", %{"post" => params}, socket) do
    changeset = Feed.change_announcement(%Post{}, params)
    {:noreply, assign(socket, :form, to_form(changeset, action: :validate))}
  end

  def handle_event("post", %{"post" => params}, socket) do
    case Feed.create_announcement(socket.assigns.current_scope, params) do
      {:ok, _post} ->
        {:noreply,
         socket
         |> put_flash(:info, "Announcement posted.")
         |> push_navigate(to: ~p"/")}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign(socket, :form, to_form(changeset))}

      {:error, :unauthorized} ->
        {:noreply, push_navigate(socket, to: ~p"/")}
    end
  end

  defp departments do
    for department <- Ecto.Enum.values(TeamMember, :department) do
      {Phoenix.Naming.humanize(department), department}
    end
  end
end
