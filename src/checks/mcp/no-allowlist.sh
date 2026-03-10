#!/usr/bin/env sh
# mcp-no-allowlist: Check that MCP servers have tool filtering configured
set -eu

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
. "$SCRIPT_DIR/../../lib/emit.sh"

CHECK_ID="mcp-no-allowlist"
TITLE="MCP servers without tool allowlist"
CATEGORY="mcp"
CLAUDE_HOME="${SENTINEL_CLAUDE_HOME:-$HOME/.claude}"

# Allow override for testing
SETTINGS_FILE="${SENTINEL_SETTINGS_FILE:-$CLAUDE_HOME/settings.json}"

if [ ! -f "$SETTINGS_FILE" ]; then
  emit_skip "$CHECK_ID" "$TITLE" "$CATEGORY"
  exit 0
fi

# Count MCP servers
server_count=$(jq '.mcpServers // {} | length' "$SETTINGS_FILE" 2>/dev/null) || server_count=0

if [ "$server_count" -eq 0 ]; then
  emit_pass "$CHECK_ID" "$TITLE" "$CATEGORY"
  exit 0
fi

# Check for allowedMcpTools or blockedMcpTools
has_filter=$(jq 'if (.allowedMcpTools != null or .blockedMcpTools != null) then 1 else 0 end' "$SETTINGS_FILE" 2>/dev/null) || has_filter=0

if [ "$has_filter" -eq 1 ]; then
  emit_pass "$CHECK_ID" "$TITLE" "$CATEGORY"
else
  evidence=$(jq -n --argjson n "$server_count" \
    '[{"type":"settings","detail":(($n | tostring) + " MCP server(s) configured with no tool filtering")}]')
  emit_warn "$CHECK_ID" "$TITLE" "$CATEGORY" "medium" \
    "$evidence" \
    '{"description":"Add allowedMcpTools to settings.json","argv":["echo","Add allowedMcpTools to ~/.claude/settings.json"],"risk":"safe"}'
fi
