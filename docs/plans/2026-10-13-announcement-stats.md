# Plan: announcement stats (2026-10-13)

**Scope and decisions:** [`docs/architecture.md`](../architecture.md), D-008. Managers see, for each announcement, how many people it was sent to, how many have seen it and how many have acknowledged it, and who.

**Branch:** `feat/announcement-stats` → `main`, opened as one PR when the work is finished.

**How we build:** one sequence of commits, test-first, each with a fresh-context review.

## Steps

1. [x] **Design.** D-008, the data model, the glossary and this plan.
2. [x] **Deliveries replace acknowledgements.**
   - **The table:** `deliveries`, with composite company foreign keys (a new unique index on `posts (id, company_id)`), unique `(team_member_id, post_id)`, an index on `post_id`, and the check that acknowledged means seen.
   - **The migration:** explicit `up` and `down` in SQL. `up` backfills deliveries for earlier announcements, carries acknowledgements over and drops their table; `down` restores them. Check that each seeded persona's "Needs your attention" is the same before and after.
   - **`Audience.members/1`:** a separate leg of the audience cross-check test. `includes/1` is checked directly against posts, since deliveries now also make posts visible.
   - **Posting:** an announcement creates its deliveries in the same transaction, and broadcasts after it commits.
   - **Reading:** "Needs your attention" and acknowledging read from deliveries. An announcement sent to you is always visible to you.
   - **Tests:**
     - Negatives: no delivery means no acknowledging, including for an announcement from before you joined.
     - Database: a cross-company delivery and an acknowledgement without seen are rejected.
3. [x] **Seen.** The live Home marks the announcements it loads in "Needs your attention" as seen, at mount and when one arrives.
   - **Tests:**
     - The static render doesn't set `seen_at`.
     - The connected mount does, and so does an arriving announcement.
     - A remount doesn't move it.
4. **Stats**, in two commits.
   - [x] **4a. In `Feed`.**
     - **Reads, manager-only by function head:** `list_announcement_stats/2` (the counts in one grouped query, paginated), `get_announcement_stats!/2` and `list_deliveries/2`. `Delivery.status/1` puts each person in one group.
     - **Broadcasts** over `announcement_stats:<company_id>`: a post, and any seen or acknowledgement update that changed rows. `subscribe_to_stats/1` is manager-only.
     - **Tests:**
       - **Negatives:** staff are refused; another company's announcement and a shout-out id aren't found; a staff scope can't subscribe; and another company's events never arrive.
       - **Positive:** a manager outside the audience sees the stats.
       - **Counts:** one person in each state, and the counts agree with the groups.
       - **Realtime:** a broadcast on post, seen and acknowledge (`assert_receive`), and none on a repeat.
   - [x] **4b. The pages.**
     - **`/announcements/stats`:** every company announcement with its counts, paginated.
     - **`/announcements/:id/stats`:** who is in each group.
     - **Access:** the pages send staff back to Home, and managers get a Stats link there.
     - **Live updates:**
       - **The list:** re-reads the rows it has loaded and adds new announcements at the top.
       - **The detail page:** ignores other ids.
     - **Seeds:** someone who has seen but not acknowledged, and a leaver, so the demo shows all four groups.
     - **Tests:** staff are sent back, and another company's id isn't found. In two connected views, staff tapping "Got it" updates the manager's pages.
5. [x] **Browser pass and wrap-up.**
   - A phone viewport (390×844), desktop and dark mode, with a head-office manager watching while a staff member and a site manager act in separate contexts.
   - The README (it still lists "who hasn't acknowledged" as future work) and the session log.
   - Push, and open the PR.
