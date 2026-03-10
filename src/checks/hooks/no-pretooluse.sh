#!/usr/bin/env sh
# hooks-no-pretooluse: Check that PreToolUse hooks cover all destructive tools
set -eu

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
. "$SCRIPT_DIR/../../lib/emit.sh"

CHECK_ID="hooks-no-pretooluse"
TITLE="PreToolUse hooks missing for destructive tools"
CATEGORY="hooks"

GLOBAL_SETTINGS="${SENTINEL_SETTINGS_FILE:-$HOME/.claude/settings.json}"
PROJECT_DIR="${SENTINEL_PROJECT_DIR:-.}"
PROJECT_SETTINGS="$PROJECT_DIR/.claude/settings.json"

# Check if at least one settings file exists
global_exists=0
project_exists=0
[ -f "$GLOBAL_SETTINGS" ] && global_exists=1
[ -f "$PROJECT_SETTINGS" ] && project_exists=1

if [ "$global_exists" -eq 0 ] && [ "$project_exists" -eq 0 ]; then
  emit_skip "$CHECK_ID" "$TITLE" "$CATEGORY"
  exit 0
fi

# Collect all PreToolUse matchers from available settings files
matchers="[]"

if [ "$global_exists" -eq 1 ]; then
  m=$(jq '.hooks.PreToolUse // [] | [.[].matcher] | map(select(. != null))' "$GLOBAL_SETTINGS" 2>/dev/null) || m="[]"
  matchers=$(jq -n --argjson a "$matchers" --argjson b "$m" '$a + $b')
fi

if [ "$project_exists" -eq 1 ]; then
  m=$(jq '.hooks.PreToolUse // [] | [.[].matcher] | map(select(. != null))' "$PROJECT_SETTINGS" 2>/dev/null) || m="[]"
  matchers=$(jq -n --argjson a "$matchers" --argjson b "$m" '$a + $b')
fi

# Deduplicate
matchers=$(printf '%s' "$matchers" | jq 'unique')

# Check coverage of the 4 destructive tools
destructive_tools='["Bash","Write","Edit","NotebookEdit"]'

missing=$(jq -n \
  --argjson tools "$destructive_tools" \
  --argjson covered "$matchers" \
  '$tools | map(select(. as $t | $covered | index($t) == null))' )

missing_count=$(printf '%s' "$missing" | jq 'length')
covered_count=$(printf '%s' "$missing" | jq --argjson tools "$destructive_tools" '$tools | length - ($missing | length)' --argjson missing "$missing")

if [ "$missing_count" -eq 4 ]; then
  # No destructive tools covered at all
  evidence=$(jq -n --argjson tools "$destructive_tools" \
    '[{"type":"hooks","detail":"No PreToolUse hooks configured for destructive tools","unguarded":$tools}]')
  emit_fail "$CHECK_ID" "$TITLE" "$CATEGORY" "critical" \
    "$evidence" \
    '{"description":"Add PreToolUse hooks for Bash, Write, Edit, NotebookEdit in ~/.claude/settings.json","argv":["vi","~/.claude/settings.json"],"risk":"safe"}'
elif [ "$missing_count" -gt 0 ]; then
  # Partial coverage
  evidence=$(jq -n --argjson missing "$missing" \
    '[{"type":"hooks","detail":"PreToolUse hooks missing for some destructive tools","missing_tools":$missing}]')
  emit_warn "$CHECK_ID" "$TITLE" "$CATEGORY" "high" \
    "$evidence" \
    '{"description":"Add PreToolUse hooks for all missing destructive tools","argv":["vi","~/.claude/settings.json"],"risk":"safe"}'
else
  emit_pass "$CHECK_ID" "$TITLE" "$CATEGORY"
fi
