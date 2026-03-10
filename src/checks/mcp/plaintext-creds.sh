#!/usr/bin/env sh
# mcp-plaintext-creds: Check MCP server env values for plaintext credentials
set -eu

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
. "$SCRIPT_DIR/../../lib/emit.sh"

CHECK_ID="mcp-plaintext-creds"
TITLE="MCP server plaintext credentials"
CATEGORY="mcp"
PROJECT_DIR="${SENTINEL_PROJECT_DIR:-.}"
CLAUDE_HOME="${SENTINEL_CLAUDE_HOME:-$HOME/.claude}"

MCP_PROJECT="$PROJECT_DIR/.mcp.json"
MCP_GLOBAL="$CLAUDE_HOME/settings.json"

# is_plaintext_secret <value> — returns 0 if value looks like a raw secret
# A value is considered plaintext if it does NOT start with $ (env var ref)
# and matches known prefixes OR is long alphanumeric (> 20 chars)
is_plaintext_secret() {
  _val="$1"
  # Env var reference — safe
  case "$_val" in
    \$*) return 1 ;;
  esac
  # Known secret prefixes
  case "$_val" in
    sk-*|key-*|token-*) return 0 ;;
  esac
  # Long alphanumeric (> 20 chars) — heuristic for raw secret
  _len=$(printf '%s' "$_val" | wc -c | tr -d ' ')
  if [ "$_len" -gt 20 ]; then
    # Must look like a token: alphanumeric + hyphens/underscores only
    _stripped=$(printf '%s' "$_val" | tr -d 'A-Za-z0-9_-')
    if [ -z "$_stripped" ]; then
      return 0
    fi
  fi
  return 1
}

# scan_file <path> — writes findings to stdout as JSON array elements
# Returns count of findings via exit code (side-effects to evidence variable)
scan_mcp_file() {
  _file="$1"
  [ -f "$_file" ] || return 0

  # Extract server names
  _servers=$(jq -r '.mcpServers // {} | keys[]' "$_file" 2>/dev/null) || return 0

  for _srv in $_servers; do
    # Extract env keys for this server
    _env_keys=$(jq -r --arg s "$_srv" '.mcpServers[$s].env // {} | keys[]' "$_file" 2>/dev/null) || continue
    for _key in $_env_keys; do
      _val=$(jq -r --arg s "$_srv" --arg k "$_key" '.mcpServers[$s].env[$k]' "$_file" 2>/dev/null) || continue
      if is_plaintext_secret "$_val"; then
        _redacted=$(redact "$_val")
        evidence=$(printf '%s' "$evidence" | jq \
          --arg d "${_srv}.${_key}=${_redacted}" \
          '. + [{"type":"mcp_env","detail":$d,"redacted":true}]')
        found=$((found + 1))
      fi
    done
  done
}

# Check if any config file exists
has_config=0
[ -f "$MCP_PROJECT" ] && has_config=1
[ -f "$MCP_GLOBAL" ] && has_config=1

if [ "$has_config" -eq 0 ]; then
  emit_skip "$CHECK_ID" "$TITLE" "$CATEGORY"
  exit 0
fi

evidence="[]"
found=0

scan_mcp_file "$MCP_PROJECT"
scan_mcp_file "$MCP_GLOBAL"

if [ "$found" -gt 0 ]; then
  emit_fail "$CHECK_ID" "$TITLE" "$CATEGORY" "critical" \
    "$evidence" \
    '{"description":"Replace plaintext value with $ENV_VAR reference in .mcp.json","argv":["echo","Replace plaintext value with $ENV_VAR reference in .mcp.json"],"risk":"safe"}'
else
  emit_pass "$CHECK_ID" "$TITLE" "$CATEGORY"
fi
