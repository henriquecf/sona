# Demo data: a fictional multi-site hospitality company, plus a second
# company that proves isolation. Run on an empty database:
#
#     mix ecto.reset
#
# Then sign in as anyone at http://localhost:4000/dev/personas (D-005).
# All names, companies and emails here are made up.

alias Sona.Accounts
alias Sona.Accounts.{Scope, User}
alias Sona.Chat
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

  people =
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
        ],
        into: %{} do
      {name, add_team_member.(harbour_lane_sites[site], name, department, role)}
    end

  ## Channels follow the org chart (D-004): nobody is added by hand.

  channel = fn company, name, site, department ->
    {:ok, channel} =
      Chat.create_channel(company, %{
        name: name,
        site_id: site && harbour_lane_sites[site].id,
        department: department
      })

    channel
  end

  everyone = channel.(harbour_lane, "Harbour Lane", nil, nil)
  soho = channel.(harbour_lane, "Soho team", "Soho", nil)
  soho_kitchen = channel.(harbour_lane, "Soho kitchen", "Soho", :kitchen)
  channel.(harbour_lane, "Shoreditch team", "Shoreditch", nil)
  channel.(harbour_lane, "Brighton team", "Brighton", nil)
  channel.(harbour_lane, "Brighton housekeeping", "Brighton", :housekeeping)
  kitchens = channel.(harbour_lane, "Kitchens", nil, :kitchen)
  channel.(harbour_lane, "Front of house", nil, :front_of_house)
  channel.(harbour_lane, "Bars", nil, :bar)

  say = fn conversation, name, body ->
    {:ok, _} = Chat.send_message(%Scope{team_member: people[name]}, conversation, %{body: body})
  end

  say.(
    everyone,
    "Maya Okafor",
    "Welcome to Sona, everyone! This is where we'll share news from across all four sites."
  )

  say.(
    everyone,
    "Tom Hayes",
    "Reminder: the autumn menu launches on Monday at every site. Tastings this Friday."
  )

  say.(
    everyone,
    "Grace O'Neill",
    "Brighton is fully booked for the weekend. Thanks for all the extra shifts, team."
  )

  say.(
    soho,
    "Priya Shah",
    "Big one tonight: 140 covers, plus a 20-person birthday at 8pm in the back room."
  )

  say.(soho, "Ana Costa", "I can stay until close if we need an extra pair of hands.")

  say.(
    soho,
    "Sofia Nowak",
    "Bar is prepped. We're low on limes, so I've ordered more for tomorrow."
  )

  say.(soho, "Priya Shah", "Thanks both. Doors at 5:30, briefing at 5:15.")

  say.(
    soho_kitchen,
    "Luca Romano",
    "Fridge 2 is running warm. Engineer is booked for 3pm, so keep it empty until then."
  )

  say.(soho_kitchen, "Kwame Mensah", "Moved everything to the walk-in. Labels are on.")
  say.(soho_kitchen, "Luca Romano", "Legend. Allergen sheet for the new specials is on the pass.")

  say.(
    kitchens,
    "Sam Taylor",
    "Anyone have a good recipe for the squash purée on the autumn menu? Ours keeps splitting."
  )

  say.(
    kitchens,
    "Mateus Silva",
    "Add the butter off the heat, a little at a time. Happy to show you at Friday's tasting."
  )

  ## Northfield Inns: a second company nobody at Harbour Lane can see

  {:ok, northfield} = Companies.create_company(%{name: "Northfield Inns"})
  {:ok, york} = Companies.create_site(northfield, %{name: "York"})

  ruth = add_team_member.(york, "Ruth Barker", :front_of_house, :manager)
  add_team_member.(york, "Owen Price", :kitchen, :staff)

  {:ok, york_team} = Chat.create_channel(northfield, %{name: "York team", site_id: york.id})

  {:ok, _} =
    Chat.send_message(%Scope{team_member: ruth}, york_team, %{
      body: "Quiz night is back on Thursday!"
    })
end
