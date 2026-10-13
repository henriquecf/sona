defmodule Sona.Feed.AnnouncementStats do
  @moduledoc """
  How an announcement is doing, for managers (D-008):

    * `sent` - everyone it was sent to.
    * `seen` - everyone who has seen it, including those who acknowledged
      it, but not people who left without acknowledging.
    * `acknowledged` - everyone who acknowledged it, including people who
      have left since.
    * `left` - people who left without acknowledging it.

  `Sona.Feed.Delivery.status/1` puts each person in one of the groups these
  count.
  """

  @enforce_keys [:post]
  defstruct [:post, sent: 0, seen: 0, acknowledged: 0, left: 0]
end
