defmodule SonaWeb.TimeComponents do
  @moduledoc """
  Components for showing times.
  """
  use Phoenix.Component

  @doc """
  A time in the reader's local time zone.

  The server renders UTC (it holds no time-zone data); a client hook
  rewrites it in the browser's zone once mounted. With `relative`, only
  today's times show the time of day; this week's show the weekday, and
  older ones the date.
  """
  attr :id, :string, required: true
  attr :at, DateTime, required: true
  attr :relative, :boolean, default: false
  attr :class, :any, default: nil

  def local_time(assigns) do
    ~H"""
    <time
      id={@id}
      phx-hook=".LocalTime"
      datetime={DateTime.to_iso8601(@at)}
      data-relative={@relative}
      class={@class}
    >
      {Calendar.strftime(@at, "%H:%M")}
    </time>
    <script :type={Phoenix.LiveView.ColocatedHook} name=".LocalTime">
      export default {
        mounted() { this.render() },
        updated() { this.render() },
        render() {
          const time = new Date(this.el.getAttribute("datetime"))
          const today = time.toDateString() === new Date().toDateString()
          const ageInDays = (Date.now() - time) / 86400000
          if (!this.el.hasAttribute("data-relative") || today) {
            this.el.textContent = time.toLocaleTimeString([], {hour: "2-digit", minute: "2-digit"})
          } else if (ageInDays < 6) {
            this.el.textContent = time.toLocaleDateString([], {weekday: "short"})
          } else {
            this.el.textContent = time.toLocaleDateString([], {day: "numeric", month: "short"})
          }
        }
      }
    </script>
    """
  end
end
