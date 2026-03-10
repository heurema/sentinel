#!/usr/bin/env sh
# mcp-unpinned-versions: Check MCP server args for unpinned package versions
set -eu

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
. "$SCRIPT_DIR/../../lib/emit.sh"

CHECK_ID="mcp-unpinned-versions"
TITLE="MCP servers with unpinned versions"
CATEGORY="mcp"
PROJECT_DIR="${SENTINEL_PROJECT_DIR:-.}"
CLAUDE_HOME="${SENTINEL_CLAUDE_HOME:-$HOME/.clone}"

MCP_PROJECT="$PROJECT_DIR/.mcp.json"
MCP_GLOBAL="$CLAUDE_HOME/settings.json"

# is_unpinned_pkg <arg> — returns 0 if @scope/pkg without @version
is_unpinned_pkg() {
  _arg="$1"
  # Must start with @ (scoped package)
  case "$_arg" in
    @*) ;;
    *) return 1 ;;
  esac
  # Extract the part after the first @scope/name — check if there's a second @ for version
  # e.g. @scope/pkg → unpinned, @scope/pkg@1.2.3 → pinned
  _without_scope="${_arg#@}"   # remove leading @
  _pkg_part="${_without_scope%%/*}"  # get scope
  _rest="${_without_scope#*/}"       # get rest after scope/
  # If rest contains @, it has a version pin
  case "$_rest" in
    *@*) return 1 ;;  # pinned
    *)   return 0 ;;  # unpinned
  esac
}

# is_unpinned_docker <command> <args_json> — returns 0 if docker image lacks :tag
is_unpinned_docker() {
  _cmd="$1"
  _args_json="$2"
  [ "$_cmd" = "docker" ] || return 1
  # Look for 'run' subcommand and image argument (last non-flag arg typically)
  _image=$(printf '%s' "$_args_json" | jq -r '[.[] | select(startswith("-") | not)] | last // ""')
  case "$_image" in
    *:*) return 1 ;;  # has tag
    ""|run) return 1 ;; # no image found
    *) return 0 ;;    # image without tag
  esac
}

scan_mcp_file() {
  _file="$1"
  [ -f "$_file" ] || return 0

  _servers=$(jq -r '.mcpServers // {} | keys[]' "$_file" 2>/dev/null) || return 0

  for _srv in $_servers; do
    _cmd=$(jq -r --arg s "$_srv" '.mcpServers[$s].command // ""' "$_file" 2>/dev/null) || continue
    _args_json=$(jq -c --arg s "$_srv" '.mcpServers[$s].args // []' "$_file" 2>/dev/null) || _args_json="[]"
    _first_arg=$(printf '%s' "$_args_json" | jq -r '.[0] // ""' 2>/dev/null) || _first_arg=""

    _unpinned=""
    if [ "$_cmd" = "npx" ] && is_unpinned_pkg "$_first_arg"; then
      _unpinned="$_first_arg"
    elif is_unpinned_docker "$_cmd" "$_args_json"; then
      _unpinned=$(printf '%s' "$_args_json" | jq -r '[.[] | select(startswith("-") | not)] | last // ""')
    fi

    if [ -n "$_unpinned" ]; then
      evidence=$(printf '%s' "$evidence" | jq \
        --arg d "${_srv}: ${_unpinned}" \
        '. + [{"type":"mcp_version","detail":$d}]')
      found=$((found + 1))
    fi
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
  emit_warn "$CHECK_ID" "$TITLE" "$CATEGORY" "medium" \
    "$evidence" \
    '{"description":"Pin version: npx @scope/pkg@1.2.3","argv":["echo","Pin version: npx @scope/pkg@1.2.3"],"risk":"safe"}'
else
  emit_pass "$CHECK_ID" "$TITLE" "$CATEGORY"
fi
