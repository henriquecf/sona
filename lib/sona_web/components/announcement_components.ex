defmodule SonaWeb.AnnouncementComponents do
  @moduledoc """
  Components for announcement stats (D-008).
  """
  use Phoenix.Component

  alias Sona.Feed.AnnouncementStats

  @doc """
  An announcement's four counts (see `Sona.Feed.AnnouncementStats`), over a
  meter of how many of those it was sent to have acknowledged it.
  """
  attr :id, :string, required: true
  attr :stats, AnnouncementStats, required: true

  def stats_summary(assigns) do
    ~H"""
    <div id={@id} class="space-y-2">
      <dl class="grid grid-cols-4 gap-2">
        <.stat name="sent" label="Sent" count={@stats.sent} />
        <.stat name="seen" label="Seen" count={@stats.seen} />
        <.stat name="acknowledged" label="Got it" count={@stats.acknowledged} />
        <.stat name="left" label="Left" count={@stats.left} />
      </dl>
      <%!-- The counts carry the numbers; the meter is for the eye. --%>
      <div aria-hidden="true" class="h-2 overflow-hidden rounded-full bg-primary/15">
        <div
          class="h-full rounded-full bg-primary transition-[width] duration-500 motion-reduce:transition-none"
          style={"width: #{percent(@stats.acknowledged, @stats.sent)}%"}
        >
        </div>
      </div>
    </div>
    """
  end

  attr :name, :string, required: true
  attr :label, :string, required: true
  attr :count, :integer, required: true

  defp stat(assigns) do
    ~H"""
    <div data-stat={@name} data-count={@count} class="rounded-box bg-base-200/70 px-2 py-1.5">
      <dt class="text-xs text-base-content/70">{@label}</dt>
      <dd class="text-lg font-semibold leading-tight tabular-nums">{@count}</dd>
    </div>
    """
  end

  defp percent(_count, 0), do: 0
  defp percent(count, total), do: round(count * 100 / total)
end
