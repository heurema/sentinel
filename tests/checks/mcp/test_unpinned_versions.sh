#!/usr/bin/env sh
set -eu
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
CHECK="$SCRIPT_DIR/../../../src/checks/mcp/unpinned-versions.sh"
FIXTURES="$SCRIPT_DIR/fixtures"

passed=0; failed=0

assert_valid_json() {
  name="$1"; json="$2"
  if printf '%s' "$json" | jq . >/dev/null 2>&1; then
    passed=$((passed + 1))
  else
    printf 'FAIL: %s — invalid JSON: %s\n' "$name" "$json"
    failed=$((failed + 1))
  fi
}

assert_field() {
  name="$1"; json="$2"; field="$3"; expected="$4"
  actual=$(printf '%s' "$json" | jq -r "$field")
  if [ "$actual" = "$expected" ]; then
    passed=$((passed + 1))
  else
    printf 'FAIL: %s — %s: expected "%s", got "%s"\n' "$name" "$field" "$expected" "$actual"
    failed=$((failed + 1))
  fi
}

# Test: .mcp.json with unpinned @scope/pkg → WARN
result=$(SENTINEL_PROJECT_DIR="$FIXTURES/project-unpinned" \
  SENTINEL_CLAUDE_HOME="$FIXTURES/no-such-dir" \
  sh "$CHECK")
assert_valid_json "unpinned - valid JSON" "$result"
assert_field "unpinned - status WARN" "$result" ".status" "WARN"
assert_field "unpinned - severity medium" "$result" ".severity" "medium"
assert_field "unpinned - evidence has server name" "$result" '.evidence[0].detail' "gh: @modelcontextprotocol/server-github"

# Test: .mcp.json with pinned @scope/pkg@version → PASS
result=$(SENTINEL_PROJECT_DIR="$FIXTURES/project-pinned" \
  SENTINEL_CLAUDE_HOME="$FIXTURES/no-such-dir" \
  sh "$CHECK")
assert_valid_json "pinned - valid JSON" "$result"
assert_field "pinned - status PASS" "$result" ".status" "PASS"

# Test: no .mcp.json → SKIP
result=$(SENTINEL_PROJECT_DIR="$FIXTURES/project-no-mcp" \
  SENTINEL_CLAUDE_HOME="$FIXTURES/no-such-dir" \
  sh "$CHECK")
assert_valid_json "no mcp - valid JSON" "$result"
assert_field "no mcp - status SKIP" "$result" ".status" "SKIP"

printf '\n%d passed, %d failed\n' "$passed" "$failed"
[ "$failed" -eq 0 ] || exit 1
