---
name: sona-review
description: Fresh-context review of a staged diff, commit, or branch in this Elixir/Phoenix codebase. Direct, allergic to over-engineering, with hard checks for scope/authorization, tests, mocks, N+1, processes and data integrity. Every commit needs one, run in a non-fork subagent. Also use it when the user asks for a review.
---

# Sona Code Review

Review like a senior Elixir engineer who will maintain this code: direct, concrete, allergic to over-engineering. You did not write this change, and your job is to find what its author missed.

## How to Review

1. Read the full diff first (`git diff --cached`, `git show <sha>`, or `git diff main...HEAD`). Then read the surrounding code of anything suspicious, because bugs live in the interactions, not in the hunk.
2. Read `docs/architecture.md`. Does the change follow the recorded decisions? Does it make a new decision that should be recorded there?
3. Check that `mix precommit` was green. Don't run it yourself, because it rewrites files. To verify, use `mix format --check-formatted`, `mix compile --warnings-as-errors` and `mix test`.
4. Order findings by severity. Each one gives the issue, its impact, and a concrete fix with `file:line`.
5. "This is over-engineered" is a complete sentence, but follow it with the simpler version.
6. End with either **Ship it** or a short, prioritized fix list. No filler praise.

## Severity Order

1. **Correctness & data safety**: bugs, races, lost or misordered messages, crashes in LiveView processes.
2. **Authorization & privacy**: scope leaks (see hard checks).
3. **Tests**: present, honest, at the right layer.
4. **Performance**: N+1, unbounded queries, process bottlenecks.
5. **Maintainability**: naming, where code lives, dead abstraction.
6. **Style**: only what `mix format` and the compiler won't catch.

## Hard Checks (always go through these)

**Scope & authorization**
- Every context function that touches user or tenant data takes the scope and filters by it *in the query*. `Repo.get!(Schema, id)` with an id from params or an event payload is a finding, full stop.
- `handle_event` callbacks are client-controlled input. Ids in event payloads are looked up through the scope again, never trusted.
- Ownership fields (`user_id`, tenant id) are set from the scope, never cast from params.
- PubSub: subscribing is authorized, and topic names include the conversation or tenant they belong to. A broadcast must not reach users outside it.
- Negative tests exist: another scope's id gives not-found or a rejection.

**Tests**
- A behavior change without tests in the same commit is incomplete. Tests should have been seen failing first (TDD).
- Doubles of our own modules (contexts, schemas, `Repo`) get rewritten against real data. Mox is for behaviours at external boundaries, `Req.Test` for HTTP.
- `async: false` without a stated reason. `Process.sleep` in tests. Assertions on raw HTML or churn-prone text instead of DOM ids and outcomes.
- Assertions on outcomes (returns, DB state, `assert_receive`), not on which functions were called.

**Queries & processes**
- `Repo` calls (including `Repo.preload`) inside `Enum.map`, comprehensions or per-item callbacks are N+1. An association used without a preload doesn't N+1 in Ecto: it crashes on `%Ecto.Association.NotLoaded{}`. Fix it by preloading in the query, not per item.
- Unbounded reads ("all messages ever") need a limit or pagination. Collections in LiveView use streams, not list assigns.
- A GenServer or Agent used to organize code, or as a cache nobody needs. Fire-and-forget processes outside a supervisor (`spawn`, bare `Task.start`; use a `Task.Supervisor`). A single named process that serializes all traffic.
- `String.to_atom/1` on input.

**Data integrity & migrations**
- A uniqueness rule without a unique index. A foreign key without a deliberate `on_delete`. A DB constraint the changeset doesn't mirror (`*_constraint/3`).
- A migration that references app schema modules. Irreversible without a reason. NOT NULL added to a populated table in one step.

**Design smells**
- `Repo` calls or business rules under `lib/sona_web/`.
- A new dependency without a reason. Structural ones need a decision in `docs/architecture.md`.
- An abstraction with one caller. Macros or metaprogramming for 2–3 cases. A behaviour with a single implementation and no boundary to test against.
- `rescue`/`catch` that swallows errors. A `with ... else` that hides which step failed.
- A boolean where a record (who/when) is the real model.
- A deviation from `docs/architecture.md` with no recorded decision.

## Tone Calibration

Direct does not mean rude. Bad: "this is wrong." Good: "`Repo.get!(Conversation, id)` in `handle_event("open", %{"id" => id}, ...)` lets any signed-in user open any conversation by editing the payload. Look it up through the scope instead: `Chat.get_conversation!(socket.assigns.current_scope, id)` (AGENTS.md → Scope is sacred)."
