#!/usr/bin/env sh
# trust-no-claudeignore: Check if .claudeignore exists in the project directory
set -eu

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
. "$SCRIPT_DIR/../../lib/emit.sh"

CHECK_ID="trust-no-claudeignore"
TITLE=".claudeignore missing — AI file access uncontrolled"
CATEGORY="trust"

PROJECT_DIR="${SENTINEL_PROJECT_DIR:-}"

# SKIP: env not set or not a directory
if [ -z "$PROJECT_DIR" ] || [ ! -d "$PROJECT_DIR" ]; then
  emit_skip "$CHECK_ID" "$TITLE" "$CATEGORY"
  exit 0
fi

if [ -f "$PROJECT_DIR/.claudeignore" ]; then
  emit_pass "$CHECK_ID" "$TITLE" "$CATEGORY"
else
  evidence=$(jq -n --arg p "$PROJECT_DIR" \
    '[{"type":"directory","path":$p,"detail":".claudeignore not found"}]')
  emit_fail "$CHECK_ID" "$TITLE" "$CATEGORY" "medium" \
    "$evidence" \
    '{"description":"Create .claudeignore to control AI file access","argv":["touch",".claudeignore"],"risk":"safe"}'
fi
