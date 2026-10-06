#!/bin/bash
# PreToolUse(Bash): blocks `git commit` until it is prefixed with
# COMMIT_REVIEWED=1, asserting precommit, docs and fresh-context review all
# ran. Flow: CLAUDE.md. PreToolUse blocks only on exit 2, message on stderr.
#
# Heredoc bodies are stripped before matching, so a heredoc commit message can
# neither trip nor satisfy the gate. Without jq, any git+commit command is blocked.
# Known gaps (agents are told not to rely on them): wrappers such
# as `bash -c '...'`, `/usr/bin/git`, `--git-dir .git` (space form), `commit -a`,
# and merge/revert/cherry-pick commits.

INPUT=$(cat)

if ! command -v jq >/dev/null 2>&1; then
  case $INPUT in
    *git*commit*) echo "BLOCKED: commit-gate.sh needs jq to inspect the command. Install jq." >&2; exit 2 ;;
  esac
  exit 0
fi

# Command text with heredoc bodies removed (delimiter line kept).
COMMAND=$(printf '%s' "$INPUT" | jq -r '.tool_input.command // ""' | awk '
  skip { t = $0; sub(/^\t*/, "", t); if (t == d) skip = 0; next }
  { print }
  match($0, /(^|[^<])<<-?[[:space:]]*["'"'"']?[A-Za-z_][A-Za-z0-9_]*/) {
    d = substr($0, RSTART, RLENGTH); sub(/^.?<<-?[[:space:]]*["'"'"']?/, "", d); skip = 1
  }')

GIT='(^|[;&|({[:space:]])git([[:space:]]+(-[Cc][[:space:]]+("[^"]*"|'"'"'[^'"'"']*'"'"'|[^[:space:]]+)|--?[[:alnum:]-]+(=[^[:space:]]*)?))*[[:space:]]+'

printf '%s\n' "$COMMAND" | grep -qE "${GIT}commit([[:space:]]|\$)" || exit 0

if printf '%s\n' "$COMMAND" | grep -qE '(^|[;&|(]|[[:space:]])COMMIT_REVIEWED=1[[:space:]]+git[[:space:]]'; then
  if printf '%s\n' "$COMMAND" | grep -qE "${GIT}add([[:space:]]|\$)"; then
    echo "BLOCKED: stage in a separate call. A 'git add' on the commit line would commit changes the review never saw." >&2
    exit 2
  fi
  exit 0
fi

exec 1>&2
cat <<'MSG'
BLOCKED: commit gate. Confirm each step, then re-run as `COMMIT_REVIEWED=1 git commit ...`.

1. Precommit: `mix precommit` ran green BEFORE staging, and `git diff` shows
   nothing unstaged for these files (precommit formats the working tree).
2. Docs: docs/architecture.md reflects any decision, domain term or settled
   open question this change introduces; if this is the session's last
   commit, today's log in docs/sessions/ is updated. Don't over-document:
   record the "why", not a restatement of the code.
3. Review: a NON-fork subagent (e.g. general-purpose; a fork inherits your
   context) reviewed `git diff --cached` against
   .claude/skills/sona-review/SKILL.md, and its findings are fixed and
   restaged (re-run precommit after fixes).

Do NOT rubber-stamp: the flag asserts all three steps actually happened.
MSG
exit 2
