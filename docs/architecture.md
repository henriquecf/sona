# Sona: Architecture & Decisions

A living record of Sona's product-specific design and the decisions behind it. Agents read it before planning a feature and update it in the same commit as any change that makes or changes a decision (see `AGENTS.md` → Git Workflow).

**Status:** not designed yet. The app is the unmodified `mix phx.new` skeleton.

## Product Context

A communications platform for hospitality businesses with two goals (from the brief):

1. **Alignment**: help the workforce feel part of something bigger than their day-to-day job.
2. **Messaging**: replace WhatsApp for internal 1-to-1 and group communication.

_Users, scope and focus for the POC: to be decided._

## System Overview

_To be designed._ Today: one Phoenix application with a domain layer (`Sona`, in `lib/sona/`) and a web layer (`SonaWeb`, in `lib/sona_web/`), Postgres via Ecto, and a LiveView UI.

## Domain Glossary

One word per concept. Code names follow this table.

| Term | Meaning | Code name |
|------|---------|-----------|
| _none yet_ | | |

## Decisions

Newest last. Each entry gives its context, the decision, and the consequences. Superseded entries stay in place, marked `Superseded by D-xxx`.

### D-001: Phoenix monolith on generator defaults (2026-10-06)

- **Context:** A proof-of-concept for real-time team communication, built in about half a day with coding agents.
- **Decision:** A single Phoenix 1.8 app (LiveView, Postgres, Tailwind) that keeps the `mix phx.new` defaults unless a later decision says otherwise. Elixir 1.20.4 / OTP 29.1.1, pinned in `.tool-versions` for mise.
- **Consequences:** Real-time fan-out (PubSub, Presence) comes without extra infrastructure, and there is one deployable. The generated code sets the house style that agents copy.

## Open Questions

_None recorded yet._
