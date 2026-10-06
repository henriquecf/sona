defmodule Sona.Companies.Audience do
  @moduledoc """
  Who a channel or post is for (D-004): one site or every site, crossed
  with one department or every department, within one company.

  Records store it as nullable `site_id` and `department` columns, where
  `nil` means "every". Membership is computed from the team member at
  query time, never copied into rows, so hires, transfers and leavers show
  up at once.
  """

  import Ecto.Query, warn: false

  alias Sona.Companies.TeamMember

  @doc """
  A query condition on the first binding, true when the record's audience
  includes the team member. Compose it with `where/3`, or inside a larger
  `dynamic/2`.
  """
  def includes(%TeamMember{company_id: company_id, site_id: site_id, department: department}) do
    dynamic(
      [r],
      r.company_id == ^company_id and
        (is_nil(r.site_id) or r.site_id == ^site_id) and
        (is_nil(r.department) or r.department == ^department)
    )
  end

  @doc """
  The four PubSub topics whose audiences include the team member: their
  site or every site, crossed with their department or every department
  (D-006).
  """
  def topics(%TeamMember{company_id: company_id, site_id: site_id, department: department}) do
    for site_id <- [site_id, nil], department <- [department, nil] do
      topic(company_id, site_id, department)
    end
  end

  @doc """
  The one PubSub topic a record with an audience is broadcast on.
  """
  def topic(%{company_id: company_id, site_id: site_id, department: department}) do
    topic(company_id, site_id, department)
  end

  defp topic(company_id, site_id, department) do
    "audience:#{company_id}:#{site_id || "all"}:#{department || "all"}"
  end
end
