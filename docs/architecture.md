# Sona: Architecture & Decisions

A living record of Sona's product-specific design and the decisions behind it. Agents read it before planning a feature and update it in the same commit as any change that makes or changes a decision (see `AGENTS.md` → Git Workflow).

**Status:** the POC is built (plan steps 1–11). It has chat (channels, direct conversations, unread counts) and a feed (acknowledged announcements, shout-outs), for frontline team members on phones. The build sequence is in [`docs/plans/2026-10-06-poc.md`](plans/2026-10-06-poc.md). In progress: announcement stats for managers (D-008, [`docs/plans/2026-10-13-announcement-stats.md`](plans/2026-10-13-announcement-stats.md)). After that, shift-awareness (see Open Questions).

## Product Context

A communications platform for hospitality businesses with two goals (from the brief):

1. **Alignment**: help the workforce feel part of something bigger than their day-to-day job.
2. **Messaging**: replace WhatsApp for internal 1-to-1 and group communication.

**Who it's for:** frontline team members of multi-site hospitality businesses. They work shifts, use their own phones, often have no work email, turn over fast, and are spread across sites and departments. Managers use the same app for now. A dedicated manager view comes next.

**The problem:**

- **WhatsApp knows nothing about the company.** People are added to groups by hand, so new starters are missing and leavers stay in. Personal phone numbers are shared, messages arrive on days off, and important posts drown in chatter with no way to tell who read them.
- **Alignment tools die because nobody opens them.** An intranet or company feed needs a daily habit to ride on.

**The POC's answer (D-002):** chat is the daily habit, and the feed is the lane for what matters.

- **Chat, built deep:** channels that follow the org chart, direct conversations, real-time delivery, unread counts.
- **Feed, kept narrow:** announcements that each person acknowledges, and shout-outs that tie a colleague's work to a company value.

## System Overview

One Phoenix application (D-001). The domain lives in contexts under `lib/sona/` and the web layer in `lib/sona_web/`.

| Context | Owns |
|---------|------|
| `Sona.Accounts` | Users, sign-in tokens and the generated `Scope` (from `phx.gen.auth`). |
| `Sona.Companies` | Companies, sites, team members, company values, and the audience rule. |
| `Sona.Chat` | Conversations, messages, read markers. |
| `Sona.Feed` | Posts, and the deliveries that record who each announcement was sent to, and when they saw and acknowledged it. |

**Dependencies:**

- `Chat` and `Feed` depend on `Companies`, and never on each other.
- `Accounts` doesn't depend on `Companies`. Instead, `SonaWeb.UserAuth` builds the scope and adds the active team member through a `Companies` function.

### Scope and authorization (D-003)

- **The scope:** `%Sona.Accounts.Scope{user, team_member}`.
- **The team gate:** routes that need a company sit in a `live_session` whose `on_mount` requires an active team member. A signed-in user without one (never invited, or has left) only reaches a "you're not on a team" page. Context functions pattern-match on `%Scope{team_member: %TeamMember{}}`.
- **Filtering:**
  - Every query filters by the team member's company. That is necessary but not enough.
  - Conversations and posts are also filtered by audience, or by being one of the two people in a direct conversation (D-004). An announcement is also visible to everyone it was sent to (D-008).
  - Posting an announcement needs the `manager` role, which `Feed` checks itself rather than relying on the screen hiding the button. Any team member can give a shout-out.
  - Announcement stats need the `manager` role too. A manager sees them for every announcement in their company, whatever its audience, including its title and body. That is a deliberate exception to the audience filter (D-008).
- **Client-supplied ids:** every id the client sends is looked up again through the scope, and each one gets a negative test:

| The client sends | It must resolve to |
|------------------|--------------------|
| A conversation id (to open it or send to it) | A conversation visible to me |
| A colleague id (to start a direct conversation) | An active team member of my company who isn't me |
| A post id (to acknowledge it) | An announcement that was sent to me |
| A post id (to see its stats, as a manager) | An announcement of my company |
| A site id and a department (the audience picker) | A site of my company, and a department from the fixed list |
| A recipient id and a company value id (a shout-out) | An active team member of my company who isn't me, and a value of my company |

### Screens

They are designed for phones first (D-007).

- **The frame:**
  - **Tabbed pages:** a header with the company and site and an account menu (Settings, the dev persona switcher, Log out), and a bottom tab bar.
  - **Pages outside the tabs:** a conversation or settings swaps both for a back bar.
  - **Toasts:** confirmations dismiss themselves after about six seconds, pausing while hovered or focused. Errors stay until dismissed.

- **Home:**
  - **"Needs your attention":** announcements sent to you that you haven't acknowledged, at the top. Loading them here counts as seeing them, on the live render only, as with chat reads. Once acknowledged, an announcement moves into the feed.
  - **The feed:** announcements and shout-outs, newest first, paginated.
  - **Managers** also get a Stats link.
- **Announcement stats (managers):**
  - **The list** (`/announcements/stats`): every announcement in the company, newest first, paginated, each with four counts:
    - **Sent:** everyone it was sent to.
    - **Seen:** everyone who has seen it, including those who acknowledged it, but not people who left without acknowledging.
    - **Acknowledged:** everyone who acknowledged it, including people who have left since.
    - **Left:** people who left without acknowledging it.
  - **One announcement** (`/announcements/:id/stats`): who is in each of four separate groups: not seen yet, seen but not acknowledged, acknowledged (with times), and left. Only the first two are outstanding.
  - **Both update live** as people see and acknowledge.
- **Chats:**
  - **The list:** your conversations, with unread counts.
  - **Reading:** opening a conversation reads it, and so does a message arriving while it's open. The first, static render doesn't count.
  - **A conversation:** its messages in real time, with older history loaded on demand.
  - **New direct conversation:** you can start one with a colleague from here.

### Real-time (D-006)

| Topic | Carries | Subscribers |
|-------|---------|-------------|
| `conversation:<id>` | New messages | The open conversation (any kind), and the chats list for channels, only for conversations fetched through the scope |
| `team_member:<id>` | Every direct message this person sends or receives, so a conversation that is new to them appears in their chats list, in every tab | That team member's chats lists |
| `audience:<company_id>:<site_id or all>:<department or all>` | New posts for that audience | Each team member, on the four audience topics that include them |
| `announcement_stats:<company_id>` | The id of an announcement whose stats changed: it was posted, or someone saw or acknowledged it | Managers' stats pages, which re-read that announcement's stats |

Offboarding and transfers disconnect the person's live sessions (D-003). That way a stale set of subscriptions can't outlive the change.

## Data Model

**Global rules:**

- **Ids:** bigint sequences, the generator default.
- **Timestamps:** `:utc_datetime`, which has only second precision. Messages and posts are therefore ordered and paginated by `id`, never by `inserted_at`.
- **Deletes:** companies and team members are never hard-deleted, so foreign keys use `on_delete: :nothing`.
- **Enums:** every `Ecto.Enum` column has a check constraint listing its values.

**Tenancy in the database:**

- **Which rows carry `company_id`:** `sites`, `team_members`, `company_values`, `conversations`, `posts` and `deliveries`.
- **Composite foreign keys:** a reference from one of those rows to another company-owned row includes `company_id`. For example, `references(:sites, with: [company_id: :company_id])`, backed by a unique index on `sites (id, company_id)`. This makes the database reject a link across companies.
- **Child rows:** `messages` and `read_markers` reach their company through their parent row. The scope sets their team member.
- **Messages:** a body of 1 to 4,000 characters. Times are stored in UTC and shown in the reader's local time by a small client-side hook, so the server needs no time-zone data.

| Table | Columns | Rules the database enforces |
|-------|---------|-----------------------------|
| `companies` | `name` | |
| `sites` | `company_id`, `name` | Unique `(company_id, name)` |
| `team_members` | `company_id`, `user_id`, `site_id`, `name`, `department`, `role`, `left_at` | At most one active team member per user: unique `user_id` where `left_at IS NULL`. The site is in the same company. |
| `company_values` | `company_id`, `name`, `description` | Unique `(company_id, name)`. Created by seeds for now, like channels. |
| `conversations` | `company_id`, `kind`, `name`, `site_id`, `department`, `team_member_a_id`, `team_member_b_id` | **Channel:** has a name and no team members. **Direct:** has no name, site or department, and `team_member_a_id < team_member_b_id`, so never with yourself. Unique `(team_member_a_id, team_member_b_id)` for direct conversations. Unique `(company_id, name)` for channels. |
| `messages` | `conversation_id`, `author_id`, `body` | Index on `(conversation_id, id)` |
| `read_markers` | `conversation_id`, `team_member_id`, `last_read_message_id` | Unique `(team_member_id, conversation_id)`, written as an upsert that only moves forward (`GREATEST`), so a late or repeated read can't make messages unread again |
| `posts` | `company_id`, `kind`, `author_id`, `title`, `body`, `site_id`, `department`, `recipient_id`, `company_value_id` | **All:** a body of 1 to 4,000 characters. **Announcement:** a title of 1 to 120 characters, and no recipient or value. **Shout-out:** has a recipient and a value, has no title, site or department (so it reaches the whole company), and the recipient isn't the author. |
| `deliveries` | `company_id`, `post_id`, `team_member_id`, `seen_at`, `acknowledged_at` | Unique `(team_member_id, post_id)`, and an index on `post_id` for stats. The post and the team member are in the delivery's company (backed by a unique index on `posts (id, company_id)`). Acknowledged means seen: `acknowledged_at IS NULL OR seen_at IS NOT NULL`. `Feed` sets each time only while it is empty, so the first is kept, and inserts deliveries only for announcements, never for the author. |

`left_at` records when someone left. It is set by offboarding at the time they leave, not scheduled ahead, so "active" means `left_at IS NULL` everywhere. Offboarding someone who has already left does nothing.

## Domain Glossary

One word per concept. Code names follow this table. In prose, people are "team members". `staff` is a role, not a synonym.

| Term | Meaning | Code name |
|------|---------|-----------|
| Company | A hospitality business using Sona, and the tenant. Every company-owned record belongs to one. | `Sona.Companies.Company` |
| Site | One of a company's locations: a restaurant, pub, hotel or the head office. | `Sona.Companies.Site` |
| Department | The part of the operation someone works in: front of house, kitchen, bar, reception, housekeeping or management. A fixed list for now. | `department` (`Ecto.Enum`) |
| Role | `staff` or `manager`. Managers post announcements and see announcement stats. | `role` (`Ecto.Enum`) |
| Team member | A person's place in a company: their name as colleagues see it, and their site, department and role. Leaving sets `left_at`. | `Sona.Companies.TeamMember` |
| Company value | One of the values a company stands for. Shout-outs recognise them. | `Sona.Companies.CompanyValue` |
| Audience | Who something is for. It is one site or every site, crossed with one department or every department, within one company. | `site_id` and `department` columns, matched by `Sona.Companies.Audience` |
| Conversation | A chat: either a channel or a direct conversation. | `Sona.Chat.Conversation` |
| Channel | A named group conversation for an audience. Membership follows the org chart, and nobody is added by hand. | `Conversation` with `kind: :channel` |
| Direct conversation | A 1-to-1 conversation. Its two team members are stored on the conversation itself. | `Conversation` with `kind: :direct` |
| Message | Something said in a conversation. | `Sona.Chat.Message` |
| Read marker | How far a team member has read a conversation: the last message they've seen. It is created on first read. | `Sona.Chat.ReadMarker` |
| Post | An item in the feed: an announcement or a shout-out. | `Sona.Feed.Post` |
| Announcement | A post from a manager to an audience, which each person it was sent to acknowledges. | `Post` with `kind: :announcement` |
| Delivery | An announcement sent to one team member. Posting creates one for each person in its audience at that moment, apart from the author. | `Sona.Feed.Delivery` |
| Seen | An announcement has been seen once it loads on the person's Home. | `Delivery.seen_at` |
| Acknowledgement | A team member confirming they read an announcement ("Got it"), and when. | `Delivery.acknowledged_at` |
| Announcement stats | For one announcement: how many it was sent to, how many have seen and acknowledged it, and who. Managers see them. | `Sona.Feed.AnnouncementStats` |
| Shout-out | A post in which one team member recognises another (the recipient) for living a company value. Everyone in the company sees it. | `Post` with `kind: :shout_out` |
| Persona switcher | A dev-only page for signing in as any seeded team member during demos. | `SonaWeb.PersonaController` at `/dev/personas` |

**Word choices:**

- "Company" rather than "organisation": it is spelling-neutral and the word hospitality uses.
- Not "group": it would collide with group chats.
- "Site": the standard UK term for a multi-site operator's locations.

## Decisions

Newest last. Each entry gives its context, the decision, and the consequences. Superseded entries stay in place, marked `Superseded by D-xxx`.

### D-001: Phoenix monolith on generator defaults (2026-10-06)

- **Context:** A proof-of-concept for real-time team communication, built in about half a day with coding agents.
- **Decision:** A single Phoenix 1.8 app (LiveView, Postgres, Tailwind) that keeps the `mix phx.new` defaults unless a later decision says otherwise. Elixir 1.20.4 / OTP 29.1.1, pinned in `.tool-versions` for mise.
- **Consequences:** Real-time fan-out (PubSub, Presence) comes without extra infrastructure, and there is one deployable. The generated code sets the house style that agents copy.

### D-002: POC scope: chat built deep, feed kept narrow, for frontline team members (2026-10-06)

- **Context:** Six shapes were considered:
  1. **Messaging only:** a commodity, and the alignment goal goes untouched.
  2. **A company feed only:** goes unread without a daily habit.
  3. **Chat plus a feed.**
  4. **One conversation model with several message kinds:** puts announcements back into the chatter they drown in, which is the WhatsApp problem, and makes message rows polymorphic.
  5. **Shift-aware communication built on a rota:** the most hospitality-specific option. Sona already sells workforce management (scheduling, time and attendance, payroll), so it owns the rota. Here it would mean seeding a fake rota, which is too much risk for half a day.
  6. **Announcements with read receipts only:** too thin to replace WhatsApp.
- **Decision:** Chat plus a feed (option 3).
  - **Chat, built deep:** channels whose membership follows the org chart, direct conversations, real-time delivery, unread counts and paginated history.
  - **Feed, kept narrow:** announcements with acknowledgements, and shout-outs tied to company values.
  - **Primary user:** a frontline team member on a phone.
  - **Next step:** shift-awareness (option 5). The audience model extends to it (see Open Questions).
- **Consequences:**
  - **Announcements can't drown:** they live in the feed rather than in chat.
  - **Two contexts:** `Chat` and `Feed` share only the company structure and the audience rule.
  - **Managers:** they use the same screens until a dedicated manager view is built.

### D-003: Company → site → team member, carried in the scope (2026-10-06)

- **Context:** Every read and write belongs to one hospitality business. People have a site, a department and a role, and turnover is high. Colleagues must not see each other's personal contact details.
- **Decision:**
  - **Multi-tenancy:** row-level, enforced by composite foreign keys (see Data Model).
  - **Identity vs employment:** a user is an identity, the email from `phx.gen.auth`. A team member is that user's employment: their name, company, site, department and role.
  - **What colleagues see:** a team member's name, never a user's email.
  - **One active team member per user.**
  - **Scope:** it carries that team member, and the rules in "Scope and authorization" apply.
  - **Departments and roles:** fixed `Ecto.Enum` lists.
  - **Offboarding:** follows the pattern `phx.gen.auth` uses after a password change.
    - **In the context:** a function sets `left_at`, deletes the user's session tokens, and returns them.
    - **In the web layer:** the caller passes those tokens to `SonaWeb.UserAuth.disconnect_sessions/1`.
    - **Result:** access ends at once, including in open tabs, and the domain never calls the web layer.
  - **Transfers and role changes:** a change of site, department or role also disconnects live sessions, so subscriptions and the role in the scope are rebuilt.
  - **Provisioning takes no scope:** creating companies, sites and team members, and offboarding, have no acting team member yet. Seeds and the console call them, and the manager view will add scoped versions.
  - **The offboarding action:** it belongs to the manager view. Until that exists, people leave through seeds or the console, which must call the same pair of functions rather than setting `left_at` by hand.
  - **Generators:**
    - `phx.gen.auth` registers only a `user` scope. We register a `company` scope (`access_path: [:team_member, :company_id]`, `schema_key: :company_id`) for use with `--scope company`. Child tables (`messages`, `read_markers`) are generated without `--scope`, because they reach their company through their parent row.
    - We replace the company-wide PubSub functions that generators emit with the D-006 topics.
    - Where the AGENTS.md section from `phx.gen.auth` says to filter by `current_scope.user`, this decision overrides it.
- **Consequences:**
  - **One database:** no per-tenant schemas or databases.
  - **Tests:** seeds and tests include two companies, so the cross-company tests are real.
  - **No company switcher:** someone who works for two employers needs one later.
  - **Departments:** a fixed list won't fit every customer (see Open Questions).

### D-004: Audiences target the org chart, shared by channels and announcements (2026-10-06)

- **Context:** WhatsApp groups are curated by hand, so new starters are missing and leavers linger. Announcements need the same targeting, such as "the kitchen at one site" or "front of house everywhere".
- **Decision:**
  - **Shape:** an audience is one site or all sites, crossed with one department or all departments. It is stored as nullable `site_id` and `department` columns on channels and posts.
  - **Membership is computed:** an audience's members are worked out from active team members at query time and never copied into membership rows. The one exception is who an announcement was sent to, recorded when it is posted (D-008).
  - **One rule, one module:** `Sona.Companies.Audience` owns every encoding of the rule: the query filter, the members of a record's audience (D-008), the four topics a team member subscribes to, and the topic a record broadcasts on. One test runs all four audience shapes through each.
  - **Authors:** they always see their own posts, even outside the audience, and never need to acknowledge their own announcements. The author may not be subscribed to the post's audience topic, so after posting they return to Home, which reloads it.
  - **New starters:** when there is no read marker, messages from before the team member joined don't count as unread. For announcements, this is superseded by D-008: a new starter has no delivery for earlier ones.
  - **Channels:** in the POC they are created by seeds. Each has a name, and several channels may share an audience.
  - **Direct conversations:** they store their pair (see Data Model).
    - **Opening:** the conversation is found or created when someone opens it. The chats list only shows a direct conversation once it has a message, so it appears for the other person with its first message.
    - **Who you can message:** an active team member of your company who isn't you.
    - **After someone leaves:** a direct conversation with them stays readable but takes no new messages.
- **Consequences:**
  - **No sync jobs:** hires, transfers and leavers show up at once.
  - **History is visible:** unlike WhatsApp, someone who joins or transfers in can read the channel's past messages.
  - **Counts use today's audience:** superseded by D-008. Announcements record who they were sent to, so "9 of 14 acknowledged" is measured against the audience when the post went out.
  - **Ad-hoc group chats:** groups of named people don't exist yet.

### D-005: Magic-link sign-in, plus a dev persona switcher (2026-10-06)

- **Context:** Frontline team members won't remember passwords, and many have only a personal email address. Demos need several people signed in at once.
- **Decision:**
  - **Sign-in:** magic links only, from `mix phx.gen.auth --live`. In development, emails land in the Swoosh mailbox.
  - **Generated password settings:** they stay as generated, along with the `bcrypt_elixir` dependency they bring, but aren't part of the product flow. The login page leads with the magic link, and the password form sits behind "Use a password instead".
  - **Opening the app signed out:** goes straight to log-in, without an error flash. Other protected pages still explain the redirect.
  - **Self-registration:** stays as generated. Someone who registers without an invitation has no team member and lands on "you're not on a team".
  - **Persona switcher:** at `/dev/personas`. It signs in as any seeded team member.
    - **Never in production:** its routes and its modules (`SonaWeb.PersonaController`, `SonaWeb.PersonaHTML`, `Sona.DevPersonas`) only compile when `dev_routes` is on. That is also enabled in `config/test.exs` so the switcher is tested.
    - **The one unscoped query:** it lists team members across companies without a scope. That deliberate exception lives in `Sona.DevPersonas`, not in a context's public API.
  - **Phone codes:** one-time codes by phone are not built.
- **Consequences:**
  - **Two paths:** the persona switcher is the demo path, and magic links are the real path.
  - **Several personas at once:** each needs its own cookies: a separate browser profile, or one normal and one private window. Private windows in Chrome and Firefox share one cookie jar.

### D-006: Real-time topics are authorized by construction (2026-10-06)

- **Context:** LiveView processes subscribe to PubSub topics. A broadcast must never reach someone outside its conversation or audience.
- **Decision:**
  - **Topics:** each one names exactly what it carries (see "Real-time" above).
  - **Subscriptions:** a LiveView subscribes only to:
    - `conversation:<id>`, for conversations it fetched through the scope.
    - Its own `team_member:<id>`.
    - The four audience topics `Audience` computes from its own team member.
    - A manager's own company's `announcement_stats:<company_id>`, through a `Feed` function that only matches managers (D-008).
  - **Broadcasts:** a post goes to the single topic of its audience. An announcement's stats changes also go to `announcement_stats:<company_id>` (D-008).
  - **No filtering on receipt:** nothing is filtered in `handle_info`.
  - **Changes that move people:** offboarding and transfers disconnect live sessions (D-003), so subscriptions can't go stale.
  - **Display order is by id, not arrival:**
    - **Why:** PubSub keeps one sender's broadcasts in order, but not broadcasts from different senders. A sender also shows their own message before its broadcast arrives.
    - **How:** messages, feed posts and pending announcements are displayed by id through CSS `order`.
    - **Trade-off:** screen readers follow DOM order, so after a rare race, or an acknowledgement, the reading order can differ from the visual order until the next load.
- **Consequences:**
  - **No permission checks in `handle_info`.**
  - **Chats list subscriptions:** one per channel plus the team member's own topic, so each message reaches a list once.
  - **Fan-out cost:**
    - **Chats lists:** each open list reloads (three queries) on every message in any of its conversations, so a channel message costs one reload per member viewing their list.
    - **Open conversations:** each one marks every arriving message read (a lookup and an upsert).
    - **Verdict:** fine for a POC. At scale, the list would update the one conversation in place, and reads would be batched.
  - **Needs your attention:** capped at 50 pending announcements. Any beyond that show up as earlier ones are acknowledged. Finding them starts from the person's own deliveries (D-008).
  - **Unread counts:** past a read marker, a count is an index range scan. A channel someone has never opened has no marker, so its count scans everything since they joined. An index on `messages (conversation_id, inserted_at)` would fix that when channels get long.
  - **Presence:** "who's online" is not built yet.

### D-007: Phone-first LiveView, no native app (2026-10-06)

- **Context:** Team members use their phones, and the POC has half a day. A production frontline app needs push notifications, which means a native app or a PWA with web push.
- **Decision:**
  - **LiveView, phone first:** server-rendered, designed for a phone (about 390px wide) with a bottom tab bar and large touch targets, and still usable on desktop.
  - **Components:**
    - **New ones:** hand-written Tailwind.
    - **Generated ones:** `core_components.ex` and the auth pages keep their daisyUI classes until we restyle them.
  - **Not in the POC:** React Native and push notifications.
- **Consequences:** One codebase, and real-time comes for free. Push notifications are the biggest gap between this POC and replacing WhatsApp (see Open Questions).

### D-008: Announcements record who they were sent to (2026-10-13)

- **Context:**
  - Managers need to know, for each announcement, who it went to, who has seen it and who has acknowledged it. Acknowledgements were recorded, but no screen showed them.
  - Under D-004, a count would be measured against today's audience, so hires, transfers and leavers would move it, and nothing recorded who the announcement actually reached. The adversarial reviews of 2026-10-13 flagged both.
- **Decision:**
  - **Deliveries:**
    - Posting an announcement inserts a delivery for each active team member in its audience, except the author, in the same transaction.
    - `Audience.members/1` is the query that finds them, a new encoding of the audience rule (D-004), so it joins the cross-check test.
    - That set is fixed: nobody is added or removed later.
  - **Seen:** an announcement is seen when it loads in "Needs your attention" on the person's live Home, at mount or when it arrives. The static first render doesn't count, as with chat reads. Acknowledging counts as seeing.
  - **Acknowledged:** `acknowledged_at` on the delivery replaces the `acknowledgements` table.
  - **Earlier announcements:** a migration backfilled their deliveries.
    - **Who:** the audience members, other than the author, who had joined and not left when it was posted, plus anyone who acknowledged it. That matches "Needs your attention" before the change.
    - **Today's site and department:** transfers aren't recorded, so the backfill can only use where people are now.
    - **Seen:** an acknowledged delivery is seen at its acknowledgement time. The rest have no `seen_at`, which for these old announcements means "unknown", not "not seen".
  - **Needs your attention:** your deliveries that you haven't acknowledged.
  - **Visibility:** still computed from the audience (D-004), plus one rule: you can always see an announcement that was sent to you.
  - **Who sees the stats:** every manager, for every announcement in the company, whatever its audience. `Feed` checks the role.
  - **Where:** a Stats link on managers' Home leads to the list and to each announcement (see Screens). Both update live over `announcement_stats:<company_id>`. Their URLs end in `/stats`, leaving `/announcements/:id` for the announcement itself.
  - **Leavers:** they stay among those it was sent to. Someone who left without acknowledging is shown as Left and no longer counts as outstanding.
- **Consequences:**
  - **Stable numbers:** "9 of 14" means 9 of the 14 people it went to, whatever has changed since.
  - **New starters:** they don't owe earlier announcements, because they have no delivery for them. This replaces the check against when they joined.
  - **Write cost:** a company-wide announcement writes one row per team member as it is posted. At 10k people that is still one `INSERT … SELECT`. Move it to a job once there is a job runner.
  - **"Seen" means loaded, not read:** a card further down a long "Needs your attention" list still counts.
  - **Monitoring data:** "seen" adds detail to what the customer records about its staff, which matters for its privacy notice under GDPR.
  - **Fan-out:** each time someone sees or acknowledges an announcement, every open stats page in the company re-reads that announcement's stats. Right after a company-wide post, that is one re-read of the whole who-list per person seeing it, on every open page for it. Fine for a POC. At scale, batch the updates.
  - **Who-lists load whole:** the page for one announcement lists everyone it was sent to. Paginate each group before company-wide announcements reach thousands.

## Open Questions

- **Shift-awareness (the next step, D-002):**
  - **Data:** a `shifts` table (team member, site, start, end), seeded until it reads Sona's rota.
  - **Features:** an "on shift now" audience, on-shift channels, pre-shift briefings with acknowledgements, and quiet hours that hold non-urgent messages until someone's next shift.
- **Manager view:**
  - Inviting, transferring and offboarding team members (D-003).
  - Posting rights per site. Today any manager can post to any audience in their company.
- **Announcement stats, next (D-008):**
  - "Goes to N people" on the announcement form, from `Audience.members/1`.
  - A Remind button, once push notifications exist.
  - Stats split by site, so each site's managers can follow their own team.
  - Paginated who-lists for company-wide announcements.
- **Push notifications:** a native app (React Native) or PWA web push. Without them, Sona can't replace WhatsApp.
- **Phone sign-in:** one-time codes by SMS for team members without an email address.
- **Departments per company:** the fixed list won't fit every business (spa, events, security). Move it to a table when a customer needs their own.
- **More than one company or site:** people who work for two companies, and team members who cover several sites.
- **Unread counts:**
  - **Other tabs:** reading in one tab doesn't clear the badge in a chats list open in another. Likewise, tapping "Got it" doesn't update the person's other open Home tabs until they reload.
  - **No cap:** counts aren't capped ("99+").
  - **Transfers:** once they exist, a transfer would need a new baseline, or channels at the new site show history since the person joined the company as unread.
- **Translation and catch-up summaries:** for multilingual crews and people coming back from days off, using an LLM API called through `Req`.
