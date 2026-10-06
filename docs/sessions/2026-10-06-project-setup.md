# 2026-10-06: Project Setup

**Agent:** Claude Code (Claude Opus 5.5), with the engineer directing.
**Goal:** Bootstrap the repository and the agent harness before any product work.

The raw transcript is not committed. This high-level summary replaces it.

## Decisions

- **Toolchain:** the latest Erlang 29.1.1 and Elixir 1.20.4-otp-29, installed and pinned with mise (`.tool-versions`, which asdf and CI setups can also read).
- **Scaffold:** `mix phx.new sona` with every default (Phoenix 1.8.15): Postgres, LiveView, Tailwind, esbuild, Swoosh, Gettext, LiveDashboard. The default branch is `main`.
- **Local database:** kept the generator's `postgres`/`postgres` config and created a matching local role, rather than editing the config.
- **Agent conventions:** established team practices, translated to Elixir/Phoenix idioms instead of copied verbatim:
  - TDD with a red → green loop, and tests shipped in the same commit.
  - "Don't mock what you own." Doubles only at boundaries, via `Req.Test` or behaviours + Mox.
  - Authorization through Phoenix 1.8 scopes.
  - Query discipline for Ecto: no lazy loading, so N+1 comes from preloads in loops.
  - Processes only for runtime needs; DB constraints mirrored in changesets.
  - Small atomic commits with a **fresh-context review before every commit**, and an architecture doc kept current.
- **Harness layout:**
  - `AGENTS.md` is the agent-agnostic source of truth. Project rules sit on top, and the Phoenix-generated usage rules stay intact below so they can be re-synced. Project rules win where they conflict, and two known errors in the generated rules are corrected (stream `at:` direction, scope-less examples).
  - `CLAUDE.md` imports `AGENTS.md` and documents the Claude Code workflow.
- **One commit gate:** a single `PreToolUse` hook blocks `git commit` until the agent confirms three steps: `mix precommit` ran before staging, the docs were checked, and a non-fork subagent reviewed the staged diff against the `sona-review` skill. We started with two gates (docs on `git add`, review on `git commit`) and merged them, so restaging after review fixes isn't blocked again.
- **Docs location:** `docs/`, not `doc/`, because ExDoc writes to `doc/` and Phoenix gitignores it.

## How the review loop went

Two fresh-context review rounds on the harness commit found real issues, which were fixed before committing.

**Round 1:**
- `mix precommit` formats the working tree, so running it after `git add` could commit unformatted code. Precommit now runs before staging.
- The hooks only parsed the first line of a command, so multi-line commands and `git -c …`/`git --no-pager …` slipped past, and without `jq` the gate failed open.
- A forked subagent would inherit the author's context, so the gate now requires a non-fork reviewer.

**Round 2 (on the fixes):**
- Ignoring everything after a heredoc hid any later `git commit`. Now only heredoc bodies are stripped.
- The flag was accepted anywhere on the line, even inside a message. Now it must prefix the `git` call.
- The no-`jq` fallback still wasn't closed. It now blocks.
- A `git add` on the flagged commit line is blocked, the remaining known gaps are listed in the hook header, and a 20-case test matrix passes.

**Other fixes across both rounds:**
- Technical wording: Ecto crashes on `NotLoaded` rather than N+1-ing; "link or supervise" processes; a generated LiveView rule had the stream `at:` direction backwards.
- Trimmed duplication: the checklist now lives only in the skill, and the product goals only in `docs/architecture.md`. Dropped a speculative migration rule.

## Built

1. `Generate Phoenix 1.8.15 app with default options`: database created, `mix test` and `mix precommit` green.
2. Agent harness: `AGENTS.md`, `CLAUDE.md`, `.claude/` (settings, commit-gate and session-start hooks, `sona-review` skill), the `docs/architecture.md` skeleton, and this log.

## Follow-ups

- Product design: scope the POC (alignment vs messaging, or both) and record it in `docs/architecture.md`.
- Optional tooling to consider, none added yet:
  - Tidewave, which gives agents runtime introspection of the running app.
  - `usage_rules`, which syncs dependency rules into `AGENTS.md`.
  - Credo.
  - A versioned git pre-commit hook running `mix precommit`, for non-Claude agents and humans.
