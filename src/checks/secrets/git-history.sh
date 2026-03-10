#!/usr/bin/env sh
# secrets-git-history: Check git history for committed .env secrets
set -eu

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
. "$SCRIPT_DIR/../../lib/emit.sh"

CHECK_ID="secrets-git-history"
TITLE="Secrets committed in git history"
CATEGORY="secrets"
PROJECT_DIR="${SENTINEL_PROJECT_DIR:-.}"

PATTERNS='_API_KEY=|_SECRET=|_TOKEN=|_PASSWORD=|ANTHROPIC_API|OPENAI_API|AWS_SECRET|GITHUB_TOKEN'

REMEDIATION='{"description":"Remove secrets from git history","argv":["git","filter-repo","--invert-paths","--path",".env"],"risk":"dangerous"}'

# UNSUPPORTED: git binary not found
if ! command -v git >/dev/null 2>&1; then
  emit_unsupported "$CHECK_ID" "$TITLE" "$CATEGORY" "git binary not found"
  exit 0
fi

# SKIP: not a git repo
if ! git -C "$PROJECT_DIR" rev-parse --git-dir >/dev/null 2>&1; then
  emit_skip "$CHECK_ID" "$TITLE" "$CATEGORY"
  exit 0
fi

evidence="[]"
found=0

# Search git history for .env files that were added containing secret patterns
# Use timeout via alarm if available; otherwise run directly (30s guidance)
matches=$(git -C "$PROJECT_DIR" log --all --diff-filter=A -p -- '*.env' '*.env.*' 2>/dev/null \
  | grep -iE "$PATTERNS" | head -10) || true

if [ -n "$matches" ]; then
  # Get the commit SHA(s) that introduced the secrets
  commits=$(git -C "$PROJECT_DIR" log --all --diff-filter=A --format="%H %h" -- '*.env' '*.env.*' 2>/dev/null | head -5) || true
  first_commit_short=$(printf '%s' "$commits" | head -1 | awk '{print $2}')
  first_commit_full=$(printf '%s' "$commits" | head -1 | awk '{print $1}')

  # Count unique secret patterns found
  pattern_count=$(printf '%s' "$matches" | wc -l | tr -d ' ')
  found=$((found + 1))
  evidence=$(printf '%s' "$evidence" | jq \
    --arg sha "${first_commit_full:-unknown}" \
    --arg d "Secrets found in git history (commit ${first_commit_short:-unknown}), ~${pattern_count} line(s) match secret patterns" \
    '. + [{"type":"runtime","detail":$d,"redacted":true}]')
fi

if [ "$found" -gt 0 ]; then
  emit_fail "$CHECK_ID" "$TITLE" "$CATEGORY" "high" "$evidence" "$REMEDIATION"
else
  emit_pass "$CHECK_ID" "$TITLE" "$CATEGORY"
fi
