defmodule Sona.Companies.CompanyValuesTest do
  use Sona.DataCase, async: true

  import Sona.CompaniesFixtures

  alias Sona.Companies

  test "list_values/1 returns only the scope's company's values, by name" do
    company = company_fixture()
    scope = company_scope_fixture(team_member_fixture(site: site_fixture(company: company)))
    company_value_fixture(company, name: "Own it")
    company_value_fixture(company, name: "Make it personal")
    company_value_fixture(company_fixture(), name: "Elsewhere")

    assert scope |> Companies.list_values() |> Enum.map(& &1.name) == [
             "Make it personal",
             "Own it"
           ]
  end

  test "names each value once within a company" do
    company = company_fixture()
    company_value_fixture(company, name: "Own it")

    attrs = %{name: "Own it", description: "We take responsibility."}

    assert {:error, changeset} = Companies.create_value(company, attrs)
    assert %{name: ["has already been taken"]} = errors_on(changeset)
    assert {:ok, _} = Companies.create_value(company_fixture(), attrs)
  end
end
