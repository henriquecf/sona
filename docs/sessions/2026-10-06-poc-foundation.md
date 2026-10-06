# 2026-10-06: POC Design and Foundation

**Agent:** Claude Code (Claude Opus 5.5), with the engineer directing.

**Goal:**

- Settle the product design for the case study.
- Build the foundation the features will sit on: auth, companies and the team gate, demo data, and the app shell.
- Stop there so the foundation can be merged before the features.

The raw transcript is not committed. This high-level summary replaces it.

## How we worked

- **Design before code.** The agent proposed six product shapes, with trade-offs, a comparison table and a recommendation. The engineer chose one, and the decisions went into `docs/architecture.md` (D-002 to D-007) before any code was written.
- **One sequence, with side tasks in parallel.** The engineer chose a single serial sequence of commits over parallel feature agents in worktrees. Work ran in parallel only where it was independent:
  - The agent drafted the next step in new files while a reviewer checked the current commit.
  - Reviewers worked from an export of the staged index, so in-progress files didn't leak into the review.
- **Test-first, then review.** Every code step from companies onward started with failing tests, which were run and checked to fail for the right reason. Every commit then got a fresh-context (non-fork) review against the `sona-review` skill. Findings were fixed before committing.
- **Browser check.** The shell was smoke-tested in Playwright at 390×844. The check found a bug the tests couldn't: Tailwind dropped the tab bar's active icon because its class name was built by interpolation.
- **PR shape.** The work started as one branch with one PR at the end. Mid-way, the engineer split it into a foundation PR (steps 1–5) and a stacked features PR, so the features can be reviewed on their own.

## Decisions

All are recorded in `docs/architecture.md`.

- **Scope (D-002):** chat built deep, feed kept narrow, for frontline team members on phones.
  - **Why:** chat is the daily habit, and the feed is where important posts can't drown.
  - **Next:** shift-aware communication (on-shift groups, briefings, quiet hours), which builds on Sona's rota.
- **Tenancy (D-003):** company → site → team member, carried in the scope.
  - **In the database:** row-level company ids, with composite foreign keys so a reference can't cross companies.
  - **One active team member per user,** guarded by a partial unique index.
  - **Offboarding:** ends access everywhere, including open tabs.
- **Audiences (D-004):** a site × department rule shared by channels and announcements. Membership is computed, not synced.
- **Sign-in (D-005):** magic links, plus a dev-only persona switcher whose code never compiles into production.
- **Real-time (D-006):** topics that are authorized by construction.
- **Interface (D-007):** phone-first LiveView, with no native app yet.

## What the reviews caught

**Design review (two rounds):**

- A leaver's open tab would have kept receiving messages.
- Generator defaults would have broadcast direct messages company-wide.
- Second-precision timestamps can't order messages, so messages are ordered by id.
- Direct-conversation rules the database couldn't enforce.

**Companies step:**

- Offboarding crashed on a microsecond `DateTime`.
- Offboarding the same person twice would have signed them out of a team they had since joined.
- Log-out landed on an error flash.
- A `MATCH FULL` foreign key that would have broken "all sites" audiences once someone copied it.

**Persona step:**

- Switcher modules leaked into production builds.
- The seeds' guard broke re-running `mix setup`.

## Built

1. `Record POC design: chat deep, feed narrow, for frontline staff`: the decisions, data model, glossary and build plan.
2. `Generate magic-link auth with phx.gen.auth --live`: committed as generated.
3. `Add companies, sites and team members behind a team gate`.
4. `Seed a demo company and add a dev persona switcher`.
5. `Add the phone-first app shell`: header, account menu, bottom tab bar, and a back bar for pages outside the tabs. Also this log.

## Follow-ups

- Steps 6–11 on `feat/poc`, after the foundation PR merges:
  - Chat: channels, direct conversations and unread counts.
  - Feed: announcements and shout-outs.
  - A browser pass, then wrap-up.
- The account menu (`<details>`) doesn't close on an outside click or on Escape yet.
