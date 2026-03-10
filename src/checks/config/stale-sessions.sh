#!/usr/bin/env sh
# config-stale-sessions: Flag Claude session directories older than 90 days
set -eu

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
. "$SCRIPT_DIR/../../lib/emit.sh"

CHECK_ID="config-stale-sessions"
TITLE="Stale Claude session data"
CATEGORY="config"

REMEDIATION='{"description":"Clean up stale Claude session data","argv":["find","~/.claude/projects","-maxdepth","1","-mtime","+90","-type","d"],"risk":"safe"}'

PROJECTS_DIR="${SENTINEL_PROJECTS_DIR:-$HOME/.claude/projects}"

# SKIP: projects directory doesn't exist
if [ ! -d "$PROJECTS_DIR" ]; then
  emit_skip "$CHECK_ID" "$TITLE" "$CATEGORY"
  exit 0
fi

THRESHOLD=$((90 * 86400))
NOW=$(date +%s)
CUTOFF=$((NOW - THRESHOLD))

stale_count=0
oldest_mtime=""
oldest_date=""

# Portable stat: Darwin uses -f %m, Linux uses -c %Y
get_mtime() {
  _dir="$1"
  if [ "$(uname)" = "Darwin" ]; then
    stat -f %m "$_dir"
  else
    stat -c %Y "$_dir"
  fi
}

for dir in "$PROJECTS_DIR"/*/; do
  [ -d "$dir" ] || continue
  mtime=$(get_mtime "$dir")
  if [ "$mtime" -lt "$CUTOFF" ]; then
    stale_count=$((stale_count + 1))
    if [ -z "$oldest_mtime" ] || [ "$mtime" -lt "$oldest_mtime" ]; then
      oldest_mtime="$mtime"
      # Format date portably
      if [ "$(uname)" = "Darwin" ]; then
        oldest_date=$(date -r "$mtime" '+%Y-%m-%d')
      else
        oldest_date=$(date -d "@$mtime" '+%Y-%m-%d')
      fi
    fi
  fi
done

if [ "$stale_count" -gt 0 ]; then
  evidence=$(jq -n --arg p "$PROJECTS_DIR" \
    --arg count "$stale_count" \
    --arg oldest "$oldest_date" \
    '[{"type":"directory","path":$p,"detail":("Found " + $count + " stale session(s), oldest: " + $oldest)}]')
  emit_warn "$CHECK_ID" "$TITLE" "$CATEGORY" "low" "$evidence" "$REMEDIATION"
else
  emit_pass "$CHECK_ID" "$TITLE" "$CATEGORY"
fi
