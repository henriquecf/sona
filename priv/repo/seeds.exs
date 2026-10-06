# Demo data: a fictional multi-site hospitality company, plus a second
# company that proves isolation. Run on an empty database:
#
#     mix ecto.reset
#
# Then sign in as anyone at http://localhost:4000/dev/personas (D-005).
# All names, companies and emails here are made up.

alias Sona.Accounts
alias Sona.Accounts.User
alias Sona.Companies
alias Sona.Repo

# Skip rather than fail, so re-running `mix setup` still finishes.
if Repo.exists?(Companies.Company) do
  IO.puts(
    "Seeds skipped: the database already has companies. Run `mix ecto.reset` to start over."
  )
else
  add_team_member = fn site, name, department, role ->
    email =
      name |> String.downcase() |> String.replace(~r/[^a-z]+/, ".") |> Kernel.<>("@sona.test")

    {:ok, user} = Accounts.register_user(%{email: email})
    user = user |> User.confirm_changeset() |> Repo.update!()

    {:ok, team_member} =
      Companies.create_team_member(site, user, %{name: name, department: department, role: role})

    team_member
  end

  ## Harbour Lane: a restaurant group with a hotel, across four sites

  {:ok, harbour_lane} = Companies.create_company(%{name: "Harbour Lane"})

  harbour_lane_sites =
    for name <- ["Head Office", "Soho", "Shoreditch", "Brighton"], into: %{} do
      {:ok, site} = Companies.create_site(harbour_lane, %{name: name})
      {name, site}
    end

  for {site, name, department, role} <- [
        {"Head Office", "Maya Okafor", :management, :manager},
        {"Head Office", "Tom Hayes", :management, :manager},
        {"Soho", "Priya Shah", :front_of_house, :manager},
        {"Soho", "Luca Romano", :kitchen, :manager},
        {"Soho", "Ana Costa", :front_of_house, :staff},
        {"Soho", "Kwame Mensah", :kitchen, :staff},
        {"Soho", "Sofia Nowak", :bar, :staff},
        {"Shoreditch", "Daniel Kim", :front_of_house, :manager},
        {"Shoreditch", "Chloe Martin", :front_of_house, :staff},
        {"Shoreditch", "Mateus Silva", :kitchen, :staff},
        {"Shoreditch", "Aisha Rahman", :bar, :staff},
        {"Brighton", "Grace O'Neill", :reception, :manager},
        {"Brighton", "Jakub Kowalski", :reception, :staff},
        {"Brighton", "Elena Popescu", :housekeeping, :staff},
        {"Brighton", "Sam Taylor", :kitchen, :staff}
      ] do
    add_team_member.(harbour_lane_sites[site], name, department, role)
  end

  ## Northfield Inns: a second company nobody at Harbour Lane can see

  {:ok, northfield} = Companies.create_company(%{name: "Northfield Inns"})
  {:ok, york} = Companies.create_site(northfield, %{name: "York"})

  add_team_member.(york, "Ruth Barker", :front_of_house, :manager)
  add_team_member.(york, "Owen Price", :kitchen, :staff)
end
