# 2026-10-13: Announcement Stats

**Agent:** Claude Code (Claude Opus 5.5), with the engineer directing.

**Goal:** let managers see, for each announcement, the full set of people it was sent to, how many have seen it and how many have acknowledged it. The work is on `feat/announcement-stats` as one PR, following [the plan](../plans/2026-10-13-announcement-stats.md).

The raw transcript is not committed. This high-level summary replaces it.

## How we worked

- **Design settled before code.** The agent proposed recording who each announcement was sent to, and listed four open choices. The engineer settled them:
  - **"Seen":** the announcement loaded on that person's page.
  - **Who sees the stats:** every manager.
  - **Leavers:** shown as Left.
  - **Where:** a separate stats page linked from Home, not numbers on the feed cards.
- **Recorded first.** The decision went into D-008 and a plan before any code. A fresh-context review of the design commit tightened it before it landed.
- **Test-first, with a fresh-context review on every commit.** The agent also mutated its own code to find tests that couldn't fail, and fixed the ones that passed anyway.
- **The migration, verified on the dev database.** On the dev database, a rollback-and-migrate round trip kept every acknowledgement. Each team member's "Needs your attention" was identical before and after.
- **A browser pass on a throwaway database.** It ran on a freshly seeded copy on port 4001, so the dev data was untouched:
  - **Size:** phone (390×844), desktop (1280) and dark mode.
  - **Three people at once:** a head-office manager watched the stats, while a staff member and a site manager acted in separate browser contexts.

## Decisions

All are recorded in D-008 in `docs/architecture.md`.

- **Deliveries:**
  - **One per person:** posting an announcement records a delivery for each active team member in its audience, apart from the author, in the same transaction.
  - **Fixed:** that set never changes afterwards, so "9 of 14" stays 9 of the 14 it went to.
  - **Acknowledgements:** they became a column on the delivery, so the `acknowledgements` table went.
- **"Needs your attention":** your unacknowledged deliveries. New starters have none for earlier announcements, so the check against when they joined went too.
- **Visibility:** still computed from the audience (D-004), plus one rule: you can always see what was sent to you.
- **Seen:** loading in "Needs your attention" on the live Home, at mount or on arrival. As with chat reads, the static first render doesn't count. Acknowledging also counts as seeing.
- **Stats:**
  - **Who:** every manager, for every company announcement, whatever its audience. That is a deliberate exception to audience filtering.
  - **Counts:** four of them, defined in `AnnouncementStats` and counted in one grouped query. `Delivery.status/1` groups the who-lists, and a test checks the two agree.
- **Real time:** `announcement_stats:<company_id>` carries only the id of an announcement whose stats changed. Only managers can subscribe, and each page re-reads through the scope.
- **Manager-only pages:** one `on_mount` hook (`:require_manager`) now gates them, including the existing announcement form. `Feed` still checks the role on every call.

## What the reviews caught

- **The design:**
  - **A NULL trap:** a check constraint written as `seen_at <= acknowledged_at` would have let a NULL through.
  - **A race:** two tabs could break the same constraint.
  - **A missing index:** nothing would have served the per-announcement stats.
  - **Stale text:** several statements elsewhere in the architecture doc no longer held.
- **Tests that couldn't fail:**
  - Keeping an earlier seen time when acknowledging.
  - Marking only the announcements that actually loaded.
  - Mapping each announcement's counts back to it on the list.
  - A cross-company delivery list that was empty for the wrong reason.
- **A paging bug:** a second "Load more" after the last page reset the list's boundary, and the page then ignored updates to older announcements.
- **Coverage of the common case:** a company with fewer than 20 announcements had no live-update test.
- **Smaller things:**
  - Two `<h1>`s on one page.
  - A component branching on its own DOM id.
  - Mixed "Got it" and "Acknowledged" wording.
  - Undocumented broadcasts.

## Built

1. `Record design for announcement stats (D-008)`
2. `Record who each announcement was sent to`: deliveries, the backfilling migration and `Audience.members/1`.
3. `Mark announcements seen when they load on Home`
4. `Compute announcement stats for managers, and tell them live`: the `Feed` API and its broadcasts.
5. `Add announcement stats pages for managers`
6. `Gate the announcement form with the manager hook too`
7. `Polish the stats list and wrap up`: a hover style found in the browser pass, the README with two new screenshots, the architecture status line, and this log.

## Follow-ups

All are in Open Questions in `docs/architecture.md`.

- **On the announcement form:** "Goes to N people", from `Audience.members/1`.
- **Remind:** a Remind button, once push notifications exist.
- **Per-site stats:** so each site's managers can follow their own team.
- **Long who-lists:** paginate them for company-wide announcements.
- **Leaving:** it doesn't refresh open stats pages until the offboarding action exists.
- **Splitting `Feed`:** move announcements into their own context before their next feature.
