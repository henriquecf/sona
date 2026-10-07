defmodule SonaWeb.TeamComponents do
  @moduledoc """
  Components for showing team members.
  """
  use Phoenix.Component

  # Listed in full so Tailwind sees every class.
  @avatar_colors [
    "bg-orange-200 text-orange-900",
    "bg-emerald-200 text-emerald-900",
    "bg-sky-200 text-sky-900",
    "bg-amber-200 text-amber-900",
    "bg-rose-200 text-rose-900",
    "bg-violet-200 text-violet-900"
  ]

  @doc """
  A round avatar with a team member's initials, coloured consistently by name.
  """
  attr :name, :string, required: true
  attr :class, :any, default: "size-9 text-sm"

  def avatar(assigns) do
    assigns =
      assign(assigns,
        initials: initials(assigns.name),
        color: Enum.at(@avatar_colors, :erlang.phash2(assigns.name, length(@avatar_colors)))
      )

    ~H"""
    <span
      aria-hidden="true"
      class={[
        "inline-flex shrink-0 select-none items-center justify-center rounded-full font-semibold",
        @color,
        @class
      ]}
    >
      {@initials}
    </span>
    """
  end

  @doc """
  A team member's first name, for greetings and message previews.
  """
  def first_name(name), do: name |> String.split() |> hd()

  @doc """
  Describes who a channel or post is for (D-004), from its `site` (loaded,
  or `nil` for every site) and `department` (`nil` for every department).
  """
  def audience_label(%{site: nil, department: nil}), do: "Everyone"
  def audience_label(%{site: site, department: nil}), do: "Everyone at #{site.name}"

  def audience_label(%{site: nil, department: department}),
    do: "#{department_name(department)}, every site"

  def audience_label(%{site: site, department: department}),
    do: "#{department_name(department)} at #{site.name}"

  defp department_name(department), do: Phoenix.Naming.humanize(department)

  defp initials(name) do
    name
    |> String.split()
    |> Enum.take(2)
    |> Enum.map_join(&String.first/1)
    |> String.upcase()
  end
end
