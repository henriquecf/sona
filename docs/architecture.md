# Sona: Architecture & Decisions

A living record of Sona's product-specific design and the decisions behind it. Agents read it before planning a feature and update it in the same commit as any change that makes or changes a decision (see `AGENTS.md` → Git Workflow).

**Status:** designed (D-002 to D-007). Built so far: authentication (plan step 2), companies, sites, team members and the team gate (step 3), and demo seeds with the persona switcher (step 4). The build sequence is in [`docs/plans/2026-10-06-poc.md`](plans/2026-10-06-poc.md).

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
| `Sona.Feed` | Posts and acknowledgements. |

**Dependencies:**

- `Chat` and `Feed` depend on `Companies`, and never on each other.
- `Accounts` doesn't depend on `Companies`. Instead, `SonaWeb.UserAuth` builds the scope and adds the active team member through a `Companies` function.

### Scope and authorization (D-003)

- **The scope:** `%Sona.Accounts.Scope{user, team_member}`.
- **The team gate:** routes that need a company sit in a `live_session` whose `on_mount` requires an active team member. A signed-in user without one (never invited, or has left) only reaches a "you're not on a team" page. Context functions pattern-match on `%Scope{team_member: %TeamMember{}}`.
- **Filtering:**
  - Every query filters by the team member's company. That is necessary but not enough.
  - Conversations and posts are also filtered by audience, or by being one of the two people in a direct conversation (D-004).
  - Posting an announcement needs the `manager` role, which `Feed` checks itself rather than relying on the screen hiding the button.
- **Client-supplied ids:** every id the client sends is looked up again through the scope, and each one gets a negative test:

| The client sends | It must resolve to |
|------------------|--------------------|
| A conversation id (to open it or send to it) | A conversation visible to me |
| A colleague id (to start a direct conversation) | An active team member of my company who isn't me |
| A post id (to acknowledge it) | An announcement visible to me |
| A site id and a department (the audience picker) | A site of my company, and a department from the fixed list |
| A recipient id and a company value id (a shout-out) | An active team member of my company who isn't me, and a value of my company |

### Screens

They are designed for phones first and use a bottom tab bar (D-007).

- **Home:**
  - **"Needs your attention":** announcements you haven't acknowledged, at the top. Once acknowledged, an announcement moves into the feed.
  - **The feed:** announcements and shout-outs, newest first, paginated.
- **Chats:**
  - **The list:** your conversations, with unread counts.
  - **A conversation:** its messages in real time, with older history loaded on demand.
  - **New direct conversation:** you can start one with a colleague from here.

### Real-time (D-006)

| Topic | Carries | Subscribers |
|-------|---------|-------------|
| `conversation:<id>` | New messages | The open conversation and the chats list, only for conversations fetched through the scope |
| `team_member:<id>` | A new direct conversation's first message, so the other person's chats list can subscribe to it | That team member's chats list |
| `audience:<company_id>:<site_id or all>:<department or all>` | New posts for that audience | Each team member, on the four audience topics that include them |

Offboarding and transfers disconnect the person's live sessions (D-003). That way a stale set of subscriptions can't outlive the change.

## Data Model

**Global rules:**

- **Ids:** bigint sequences, the generator default.
- **Timestamps:** `:utc_datetime`, which has only second precision. Messages and posts are therefore ordered and paginated by `id`, never by `inserted_at`.
- **Deletes:** companies and team members are never hard-deleted, so foreign keys use `on_delete: :nothing`.
- **Enums:** every `Ecto.Enum` column has a check constraint listing its values.

**Tenancy in the database:**

- **Which rows carry `company_id`:** `sites`, `team_members`, `company_values`, `conversations` and `posts`.
- **Composite foreign keys:** a reference from one of those rows to another company-owned row includes `company_id`. For example, `references(:sites, with: [company_id: :company_id])`, backed by a unique index on `sites (id, company_id)`. This makes the database reject a link across companies.
- **Child rows:** `messages`, `read_markers` and `acknowledgements` reach their company through their parent row. The scope sets their team member.

| Table | Columns | Rules the database enforces |
|-------|---------|-----------------------------|
| `companies` | `name` | |
| `sites` | `company_id`, `name` | Unique `(company_id, name)` |
| `team_members` | `company_id`, `user_id`, `site_id`, `name`, `department`, `role`, `left_at` | At most one active team member per user: unique `user_id` where `left_at IS NULL`. The site is in the same company. |
| `company_values` | `company_id`, `name`, `description` | Unique `(company_id, name)` |
| `conversations` | `company_id`, `kind`, `name`, `site_id`, `department`, `team_member_a_id`, `team_member_b_id` | **Channel:** has a name and no team members. **Direct:** has no name, site or department, and `team_member_a_id < team_member_b_id`, so never with yourself. Unique `(team_member_a_id, team_member_b_id)` for direct conversations. Unique `(company_id, name)` for channels. |
| `messages` | `conversation_id`, `author_id`, `body` | Index on `(conversation_id, id)` |
| `read_markers` | `conversation_id`, `team_member_id`, `last_read_message_id` | Unique `(conversation_id, team_member_id)`, written as an upsert |
| `posts` | `company_id`, `kind`, `author_id`, `body`, `site_id`, `department`, `recipient_id`, `company_value_id` | **Announcement:** no recipient or value. **Shout-out:** has a recipient and a value, has no site or department (so it reaches the whole company), and the recipient isn't the author. |
| `acknowledgements` | `post_id`, `team_member_id`, `inserted_at` | Unique `(post_id, team_member_id)`, inserted with `on_conflict: :nothing`. `Feed` checks that the post is an announcement. |

`left_at` records when someone left. It is set by offboarding at the time they leave, not scheduled ahead, so "active" means `left_at IS NULL` everywhere. Offboarding someone who has already left does nothing.

## Domain Glossary

One word per concept. Code names follow this table. In prose, people are "team members". `staff` is a role, not a synonym.

| Term | Meaning | Code name |
|------|---------|-----------|
| Company | A hospitality business using Sona, and the tenant. Every company-owned record belongs to one. | `Sona.Companies.Company` |
| Site | One of a company's locations: a restaurant, pub, hotel or the head office. | `Sona.Companies.Site` |
| Department | The part of the operation someone works in: front of house, kitchen, bar, reception, housekeeping or management. A fixed list for now. | `department` (`Ecto.Enum`) |
| Role | `staff` or `manager`. Managers post announcements. | `role` (`Ecto.Enum`) |
| Team member | A person's place in a company: their name as colleagues see it, and their site, department and role. Leaving sets `left_at`. | `Sona.Companies.TeamMember` |
| Company value | One of the values a company stands for. Shout-outs recognise them. | `Sona.Companies.CompanyValue` |
| Audience | Who something is for. It is one site or every site, crossed with one department or every department, within one company. | `site_id` and `department` columns, matched by `Sona.Companies.Audience` |
| Conversation | A chat: either a channel or a direct conversation. | `Sona.Chat.Conversation` |
| Channel | A named group conversation for an audience. Membership follows the org chart, and nobody is added by hand. | `Conversation` with `kind: :channel` |
| Direct conversation | A 1-to-1 conversation. Its two team members are stored on the conversation itself. | `Conversation` with `kind: :direct` |
| Message | Something said in a conversation. | `Sona.Chat.Message` |
| Read marker | How far a team member has read a conversation: the last message they've seen. It is created on first read. | `Sona.Chat.ReadMarker` |
| Post | An item in the feed: an announcement or a shout-out. | `Sona.Feed.Post` |
| Announcement | A post from a manager to an audience, which each person in it acknowledges. | `Post` with `kind: :announcement` |
| Acknowledgement | The record that a team member read an announcement, and when. | `Sona.Feed.Acknowledgement` |
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
  - **Transfers:** a change of site or department also disconnects live sessions, so subscriptions are rebuilt.
  - **Provisioning takes no scope:** creating companies, sites and team members, and offboarding, have no acting team member yet. Seeds and the console call them, and the manager view will add scoped versions.
  - **The offboarding action:** it belongs to the manager view. Until that exists, people leave through seeds or the console, which must call the same pair of functions rather than setting `left_at` by hand.
  - **Generators:**
    - `phx.gen.auth` registers only a `user` scope. We register a `company` scope (`access_path: [:team_member, :company_id]`, `schema_key: :company_id`) for use with `--scope company`. Child tables (`messages`, `read_markers`, `acknowledgements`) are generated without `--scope`, because they reach their company through their parent row.
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
  - **Membership is computed:** an audience's members are worked out from active team members at query time and never copied into membership rows.
  - **One rule, one module:** `Sona.Companies.Audience` owns every encoding of the rule: the query filter, the four topics a team member subscribes to, and the topic a record broadcasts on. One test runs all four audience shapes through each.
  - **Authors:** they always see their own posts, even outside the audience, and never need to acknowledge their own announcements. The author's view inserts its own post when it is created, because the author may not be subscribed to the post's audience topic.
  - **New starters:** when there is no read marker, messages and announcements from before the team member joined don't count as unread or as needing attention.
  - **Channels:** in the POC they are created by seeds. Each has a name, and several channels may share an audience.
  - **Direct conversations:** they store their pair (see Data Model).
    - **Opening:** the conversation is found or created when someone opens it. The chats list only shows a direct conversation once it has a message, so it appears for the other person with its first message.
    - **Who you can message:** an active team member of your company who isn't you.
    - **After someone leaves:** a direct conversation with them stays readable but takes no new messages.
- **Consequences:**
  - **No sync jobs:** hires, transfers and leavers show up at once.
  - **History is visible:** unlike WhatsApp, someone who joins or transfers in can read the channel's past messages.
  - **Counts use today's audience:** "9 of 14 acknowledged" is measured against today's audience, not the audience when the post went out.
  - **Ad-hoc group chats:** groups of named people don't exist yet.

### D-005: Magic-link sign-in, plus a dev persona switcher (2026-10-06)

- **Context:** Frontline team members won't remember passwords, and many have only a personal email address. Demos need several people signed in at once.
- **Decision:**
  - **Sign-in:** magic links only, from `mix phx.gen.auth --live`. In development, emails land in the Swoosh mailbox.
  - **Generated password settings:** they stay as generated, along with the `bcrypt_elixir` dependency they bring, but aren't part of the product flow.
  - **Self-registration:** stays as generated. Someone who registers without an invitation has no team member and lands on "you're not on a team".
  - **Persona switcher:** at `/dev/personas`. It signs in as any seeded team member.
    - **Never in production:** its routes and its modules (`SonaWeb.PersonaController`, `SonaWeb.PersonaHTML`, `Sona.DevPersonas`) only compile when `dev_routes` is on. That is also enabled in `config/test.exs` so the switcher is tested.
    - **The one unscoped query:** it lists team members across companies without a scope. That deliberate exception lives in `Sona.DevPersonas`, not in a context's public API.
  - **Phone codes:** one-time codes by phone are not built.
- **Consequences:**
  - **Two paths:** the persona switcher is the demo path, and magic links are the real path.
  - **Several personas at once:** each needs its own browser profile or private window, because one cookie holds one session.

### D-006: Real-time topics are authorized by construction (2026-10-06)

- **Context:** LiveView processes subscribe to PubSub topics. A broadcast must never reach someone outside its conversation or audience.
- **Decision:**
  - **Topics:** each one names exactly what it carries (see "Real-time" above).
  - **Subscriptions:** a LiveView subscribes only to:
    - `conversation:<id>`, for conversations it fetched through the scope.
    - Its own `team_member:<id>`.
    - The four audience topics `Audience` computes from its own team member.
  - **Broadcasts:** a post goes to the single topic of its audience.
  - **No filtering on receipt:** nothing is filtered in `handle_info`.
  - **Changes that move people:** offboarding and transfers disconnect live sessions (D-003), so subscriptions can't go stale.
- **Consequences:**
  - **No permission checks in `handle_info`.**
  - **Chats list subscriptions:** one per conversation, which is fine for the handful each team member has.
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

## Open Questions

- **Shift-awareness (the next step, D-002):**
  - **Data:** a `shifts` table (team member, site, start, end), seeded until it reads Sona's rota.
  - **Features:** an "on shift now" audience, on-shift channels, pre-shift briefings with acknowledgements, and quiet hours that hold non-urgent messages until someone's next shift.
- **Manager view:**
  - Who hasn't acknowledged an announcement.
  - Inviting, transferring and offboarding team members (D-003).
  - Posting rights per site. Today any manager can post to any audience in their company.
- **Push notifications:** a native app (React Native) or PWA web push. Without them, Sona can't replace WhatsApp.
- **Phone sign-in:** one-time codes by SMS for team members without an email address.
- **Departments per company:** the fixed list won't fit every business (spa, events, security). Move it to a table when a customer needs their own.
- **More than one company or site:** people who work for two companies, and team members who cover several sites.
- **Translation and catch-up summaries:** for multilingual crews and people coming back from days off, using an LLM API called through `Req`.
