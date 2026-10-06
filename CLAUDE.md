@AGENTS.md

## Claude Code: Commit Workflow

One hook, `.claude/hooks/commit-gate.sh` (wired in `.claude/settings.json`), blocks `git commit` until you confirm three steps. Run `git add` and `git commit` as **separate Bash tool calls**, and put nothing else on the commit's command line, so the gate sees the commit on its own.

1. **Precommit before staging.** Run `mix precommit` and get it green, *then* `git add`. Precommit formats the working tree, so running it after staging can commit unformatted code.
2. **Docs.** Make sure `docs/architecture.md` reflects any decision, domain term or settled open question the change introduces. On the session's last commit, update today's log in `docs/sessions/`.
3. **Fresh-context review.** Spawn a **non-fork** subagent with the Agent tool (e.g. `general-purpose`; a fork inherits your context and biases). Have it review `git diff --cached` against `.claude/skills/sona-review/SKILL.md`. Fix the findings, re-run `mix precommit`, and restage.

Then commit with `COMMIT_REVIEWED=1`:

```
Bash: mix precommit
Bash: git add lib/sona/chat.ex test/sona/chat_test.exs
Bash: git commit -m "..."                       # blocked with the checklist
# ... docs check; fresh-context subagent reviews the staged diff; fix, precommit, restage ...
Bash: COMMIT_REVIEWED=1 git commit -m "..."
```

**Never set `COMMIT_REVIEWED=1` without doing all three steps.** The flag asserts that the work happened. It is not a bypass switch.
