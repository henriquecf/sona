# 2026-10-06/07: POC Features

**Agent:** Claude Code (Claude Opus 5.5), with the engineer directing.

**Goal:** build the POC's features on top of the merged foundation (plan steps 6–11): chat, the feed, a browser pass and wrap-up. They go on `feat/poc` as one PR.

The raw transcript is not committed. This high-level summary replaces it.

## How we worked

- **Autonomous, step by step.** After the foundation PR merged, the engineer asked the agent to work through the remaining steps without stopping, and to validate with every available tool when automated tests weren't enough.
- **Test-first, with a fresh-context review on every commit.** Reviews ran in background agents while the next step's tests were drafted in the scratchpad, so they never touched the staged diff.
  - **The reviewers checked their own claims.** They exported the staged files to a scratch copy, mutated the code to find tests that couldn't fail, and ran `EXPLAIN ANALYZE` on synthetic data.
  - **Findings were fixed test-first,** before committing.
- **Playwright, at phone size and with two sessions.** Every user-facing step was checked at 390×844 with two browser contexts for real time. The browser pass added desktop (1280) and dark mode, plus the real magic-link sign-in.
- **A full QA run at the end.** The engineer asked for the whole app to be exercised as different people at once. A background agent drove up to 11 personas in real time on fresh seed data.
  - **Covered:** audience rules for 10 personas, three-way chat, more than 50 messages, direct messages from both sides, announcements to every audience shape, shout-outs across sites, sign-in, registration, isolation, dark mode and desktop.
  - **Found:** four bugs, fixed below, plus a list of UX ideas.
  - **Also captured:** the README screenshots.

## Decisions

All are recorded in `docs/architecture.md`.

- **Direct conversations (D-004):**
  - **Storage:** the pair is stored on the conversation, in id order, behind a partial unique index. Find-or-create uses `ON CONFLICT DO NOTHING`.
  - **First message:** a conversation stays out of both chats lists until it has one.
  - **Leavers:** once someone leaves, the conversation is read-only.
- **Real-time topics (D-006):**
  - **The chats list:** subscribes to each of its channels and to its own `team_member:<id>` topic, which carries every direct message its person sends or receives. Each message reaches a list exactly once, in every tab.
  - **Posts:** go to their one audience topic. Each Home subscribes to the four topics that include its team member.
- **Unread counts:**
  - **Read markers:** one row per person per conversation, upserted forward-only (`GREATEST`).
  - **New starters:** without a marker, only messages since someone joined count, so they aren't handed a channel's whole history.
- **Feed:**
  - **Announcements:** manager-only, checked in `Feed`. Acknowledgements are records of who and when, keeping the first time.
  - **Shout-outs:** anyone can give one, for a company value, company-wide. They never need acknowledging.
  - **The database enforces the shape of each post kind.**

## What the reviews caught

**Correctness and authorization:**

- **A lost message:** the conversation view loaded history before subscribing, so a message could slip in between.
- **A weaker write path:** `send_message` only checked the company, not the audience.
- **Duplicate deliveries:** direct messages arrived twice in the recipient's chats list, while the sender's other tabs missed new conversations.
- **Disclosures collapsing:** both `<details>` elements (the account menu and the password form) closed on every LiveView re-render, because morphdom drops the client-side `open` attribute. The browser pass missed it; the reviewer reproduced it, and it is fixed with `ignore_attributes("open")`.
- **Database holes:**
  - An announcement without a title passed the check constraint, because CHECK passes on NULL.
  - Most of the post-shape rules were untested.

**Performance, measured on synthetic data:**

- **Latest messages:** `DISTINCT ON` read every message on every chats-list reload (120 ms on 320k rows). It now uses a lateral `LIMIT 1` (0.23 ms).
- **Unread counts:** they scanned whole channels (40 ms on 500k rows). They now use a lateral index range scan (0.14 ms).

**Tests that couldn't fail:**

- **Unread counts:** a colleague's read marker counting as yours.
- **Load older:** messages out of order.
- **Shout-out shape:** the database's rules for each post kind.
- **Broadcast isolation:** another company's broadcast was only excluded by accident.

**The harness itself:**

- **The formatter's cache:** `mix format` keeps a timestamp manifest and skipped a test file that had been moved in with `mv`, so precommit passed on unformatted code.
- **The first fix didn't work:** adding a second `format` task did nothing, because a Mix alias runs each task once.
- **The fix:** `format --force`, verified with a stale probe file.

## Built

**Chat, and a harness fix found along the way:**

1. `Add channels with real-time messages`
2. `Add direct conversations between colleagues`
3. `Make precommit format every file, not just recently changed ones` (harness)
4. `Show unread counts in the chats list`

**Feed:**

5. `Add announcements that each person acknowledges`
6. `Add shout-outs that recognise colleagues for company values`

**Finish:**

7. `Polish what the browser pass found`:
   - No error when opening the app signed out.
   - The magic link comes first on the login page.
   - Readable toasts that dismiss themselves.
   - Bars sized to the frame.
   - An account menu that closes.
8. `Fix what the full browser run found`:
   - A conversation opened from the chats list started at the top: LiveView resets the scroll after navigation.
   - Near-simultaneous messages showed in different orders for different people.
   - A long unbroken announcement title widened the page and hid the tab bar.
   - An acknowledged announcement jumped to the top of the feed.
9. `Write the README and session log, and add screenshots`

## Follow-ups

- **Shift-awareness (D-002's next step):** on-shift audiences, pre-shift briefings and quiet hours.
- **Manager view:**
  - Who hasn't acknowledged an announcement ("9 of 14").
  - Inviting, transferring and offboarding people.
  - Posting rights per site.
- **Push notifications and phone sign-in:** the biggest gaps before this could replace WhatsApp.
- **UX ideas from the QA run, good candidates for live iteration:**
  - **Safer announcements:** default the audience to the manager's own site, show "goes to N people", and allow editing and deleting.
  - **Tab-bar badges:** for unread chats and announcements waiting for you.
  - **Composer:** multi-line messages and clickable links.
  - **Messages:** grouped by author, with date separators.
  - **Cross-site context:** sites shown next to names in cross-site channels and on shout-outs.
  - **Sign-in:** a branded flow, greeting people by name, without "Sign up".
- **iOS Safari:** the account menu's outside tap was checked in Chromium's mobile emulation only.
- **Smaller items:** see Open Questions and D-006's consequences in `docs/architecture.md`.
  - Unread badges across tabs, and a "99+" cap.
  - The chats list updating in place instead of reloading.
  - Translation for multilingual crews.
