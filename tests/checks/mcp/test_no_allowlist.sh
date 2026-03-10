#!/usr/bin/env sh
set -eu
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
CHECK="$SCRIPT_DIR/../../../src/checks/mcp/no-allowlist.sh"
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

# Test: settings.json with MCP servers but no allowlist → WARN
result=$(SENTINEL_CLAUDE_HOME="$FIXTURES" \
  SENTINEL_SETTINGS_FILE="$FIXTURES/settings-no-allowlist.json" \
  sh "$CHECK")
assert_valid_json "no allowlist - valid JSON" "$result"
assert_field "no allowlist - status WARN" "$result" ".status" "WARN"
assert_field "no allowlist - severity medium" "$result" ".severity" "medium"

# Test: settings.json with allowedMcpTools configured → PASS
result=$(SENTINEL_CLAUDE_HOME="$FIXTURES" \
  SENTINEL_SETTINGS_FILE="$FIXTURES/settings-with-allowlist.json" \
  sh "$CHECK")
assert_valid_json "with allowlist - valid JSON" "$result"
assert_field "with allowlist - status PASS" "$result" ".status" "PASS"

# Test: settings.json with no MCP servers → PASS
result=$(SENTINEL_CLAUDE_HOME="$FIXTURES" \
  SENTINEL_SETTINGS_FILE="$FIXTURES/settings-no-mcp.json" \
  sh "$CHECK")
assert_valid_json "no mcp servers - valid JSON" "$result"
assert_field "no mcp servers - status PASS" "$result" ".status" "PASS"

# Test: settings.json doesn't exist → SKIP
result=$(SENTINEL_CLAUDE_HOME="$FIXTURES/no-such-dir" \
  SENTINEL_SETTINGS_FILE="$FIXTURES/no-such-dir/settings.json" \
  sh "$CHECK")
assert_valid_json "no settings - valid JSON" "$result"
assert_field "no settings - status SKIP" "$result" ".status" "SKIP"

printf '\n%d passed, %d failed\n' "$passed" "$failed"
[ "$failed" -eq 0 ] || exit 1
