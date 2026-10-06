#!/bin/bash
# Hook: SessionStart (fires on startup, /clear, resume and compaction).
# Points the agent at the architecture doc and the latest session logs so
# planning starts from recorded decisions.

ROOT="${CLAUDE_PROJECT_DIR:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}"
ARCH="$ROOT/docs/architecture.md"
SESSIONS="$ROOT/docs/sessions"

if [ -f "$ARCH" ]; then
  echo "Product & architecture decisions: docs/architecture.md"
  grep -E '^### D-[0-9]+' "$ARCH" | sed 's/^### /  - /'
  echo ""
  echo "Read it before planning a feature; record new decisions there in the same commit."
else
  echo "docs/architecture.md is missing. AGENTS.md expects it to hold product decisions."
fi

if [ -d "$SESSIONS" ] && ls "$SESSIONS"/*.md >/dev/null 2>&1; then
  echo ""
  echo "Recent session logs (docs/sessions/):"
  ls -1 "$SESSIONS"/*.md | sort | tail -3 | sed "s|$ROOT/|  - |"
fi
