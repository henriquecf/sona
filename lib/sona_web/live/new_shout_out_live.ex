defmodule SonaWeb.NewShoutOutLive do
  use SonaWeb, :live_view

  alias Sona.{Companies, Feed}
  alias Sona.Feed.Post

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope} back={~p"/"}>
      <:title>Give a shout-out</:title>

      <p :if={@values == []} id="no-values" class="py-12 text-center text-base-content/70">
        Your company hasn't shared its values on Sona yet.
      </p>

      <.form
        :if={@values != []}
        for={@form}
        id="shout-out-form"
        phx-change="validate"
        phx-submit="post"
        class="space-y-1"
      >
        <.input
          field={@form[:recipient_id]}
          type="select"
          label="Who do you want to recognise?"
          prompt="Choose a colleague"
          options={@colleagues}
          required
        />

        <fieldset class="mb-2 space-y-2">
          <legend class="mb-1 text-sm font-medium">Which of our values did they live?</legend>
          <label
            :for={value <- @values}
            id={"value-#{value.id}"}
            class="flex min-h-11 cursor-pointer gap-3 rounded-box border border-base-300 p-3 transition hover:bg-base-200 has-[:checked]:border-secondary has-[:checked]:bg-secondary/10"
          >
            <input
              type="radio"
              name={@form[:company_value_id].name}
              value={value.id}
              checked={to_string(@form[:company_value_id].value) == to_string(value.id)}
              class="mt-1 accent-[var(--color-secondary)]"
            />
            <span>
              <span class="block font-semibold">{value.name}</span>
              <span class="block text-sm text-base-content/70">{value.description}</span>
            </span>
          </label>
          <p
            :for={error <- value_errors(@form)}
            class="flex items-center gap-2 text-sm text-error"
          >
            <.icon name="hero-exclamation-circle" class="size-5" /> {error}
          </p>
        </fieldset>

        <.input
          field={@form[:body]}
          type="textarea"
          label="What did they do?"
          rows="4"
          required
        />

        <button
          type="submit"
          class="inline-flex min-h-11 w-full items-center justify-center gap-2 rounded-full bg-secondary px-4 font-semibold text-secondary-content transition hover:brightness-110 active:scale-95 phx-submit-loading:opacity-60"
        >
          <.icon name="hero-sparkles" class="size-5" /> Share with everyone
        </button>
      </.form>
    </Layouts.app>
    """
  end

  @impl true
  def mount(_params, _session, socket) do
    scope = socket.assigns.current_scope

    colleagues =
      for colleague <- Companies.list_colleagues(scope) do
        {"#{colleague.name} · #{colleague.site.name}", colleague.id}
      end

    {:ok,
     socket
     |> assign(:page_title, "Give a shout-out")
     |> assign(:colleagues, colleagues)
     |> assign(:values, Companies.list_values(scope))
     |> assign(:form, to_form(Feed.change_shout_out()))}
  end

  @impl true
  def handle_event("validate", %{"post" => params}, socket) do
    changeset = Feed.change_shout_out(%Post{}, params)
    {:noreply, assign(socket, :form, to_form(changeset, action: :validate))}
  end

  # The colleague and value ids come from the client; Feed resolves them
  # within the scope's company.
  def handle_event("post", %{"post" => params}, socket) do
    case Feed.create_shout_out(socket.assigns.current_scope, params) do
      {:ok, _post} ->
        {:noreply,
         socket
         |> put_flash(:info, "Shout-out shared.")
         |> push_navigate(to: ~p"/")}

      {:error, changeset} ->
        {:noreply, assign(socket, :form, to_form(changeset))}
    end
  end

  defp value_errors(form) do
    if Phoenix.Component.used_input?(form[:company_value_id]) or form.source.action do
      Enum.map(form[:company_value_id].errors, &translate_error/1)
    else
      []
    end
  end
end
