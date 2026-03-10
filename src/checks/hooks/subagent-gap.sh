#!/usr/bin/env sh
# hooks-subagent-gap: Warn when PreToolUse hooks won't be inherited by subagents (bug #21460)
set -eu

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
. "$SCRIPT_DIR/../../lib/emit.sh"

CHECK_ID="hooks-subagent-gap"
TITLE="PreToolUse hooks not inherited by subagents (bug #21460)"
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

# Count PreToolUse hooks across both settings files
hook_count=0

if [ "$global_exists" -eq 1 ]; then
  n=$(jq '.hooks.PreToolUse // [] | length' "$GLOBAL_SETTINGS" 2>/dev/null) || n=0
  hook_count=$((hook_count + n))
fi

if [ "$project_exists" -eq 1 ]; then
  n=$(jq '.hooks.PreToolUse // [] | length' "$PROJECT_SETTINGS" 2>/dev/null) || n=0
  hook_count=$((hook_count + n))
fi

if [ "$hook_count" -eq 0 ]; then
  # No PreToolUse hooks — nothing to inherit, not a concern
  emit_pass "$CHECK_ID" "$TITLE" "$CATEGORY"
  exit 0
fi

# Check for subagent usage indicators
subagent_indicator=""

# Check CLAUDE.md in project root
if [ -f "$PROJECT_DIR/CLAUDE.md" ]; then
  if grep -qiE "Agent tool|subagent" "$PROJECT_DIR/CLAUDE.md" 2>/dev/null; then
    subagent_indicator="CLAUDE.md mentions Agent tool or subagent"
  fi
fi

# Check AGENTS.md in project root
if [ -z "$subagent_indicator" ] && [ -f "$PROJECT_DIR/AGENTS.md" ]; then
  subagent_indicator="AGENTS.md present in project root"
fi

# Check .claude/agents/ directory
if [ -z "$subagent_indicator" ] && [ -d "$PROJECT_DIR/.claude/agents" ]; then
  subagent_indicator=".claude/agents/ directory exists"
fi

if [ -z "$subagent_indicator" ]; then
  emit_pass "$CHECK_ID" "$TITLE" "$CATEGORY"
  exit 0
fi

# Subagents detected + PreToolUse hooks present → WARN
evidence=$(jq -n \
  --arg ind "$subagent_indicator" \
  --argjson count "$hook_count" \
  '[{"type":"hooks","detail":"PreToolUse hooks present but not inherited by subagents due to Claude Code bug #21460","hook_count":$count,"subagent_indicator":$ind}]')
emit_warn "$CHECK_ID" "$TITLE" "$CATEGORY" "high" \
  "$evidence" \
  '{"description":"This is a known Claude Code bug (#21460) — hooks are not inherited by subagents. No workaround available; add explicit hook calls inside subagent CLAUDE.md or avoid security-critical hooks in multi-agent setups.","argv":[],"risk":"safe"}'
