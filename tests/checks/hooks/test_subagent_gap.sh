#!/usr/bin/env sh
set -eu
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
CHECK="$SCRIPT_DIR/../../../src/checks/hooks/subagent-gap.sh"
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

# Test: subagents detected + PreToolUse hooks → WARN/high
result=$(SENTINEL_SETTINGS_FILE="$FIXTURES/with-subagents/settings.json" \
  SENTINEL_PROJECT_DIR="$FIXTURES/with-subagents" \
  sh "$CHECK")
assert_valid_json "with-subagents - valid JSON" "$result"
assert_field "with-subagents - status WARN" "$result" ".status" "WARN"
assert_field "with-subagents - severity high" "$result" ".severity" "high"

# Test: hooks exist but no subagents → PASS
result=$(SENTINEL_SETTINGS_FILE="$FIXTURES/no-subagents/settings.json" \
  SENTINEL_PROJECT_DIR="$FIXTURES/no-subagents" \
  sh "$CHECK")
assert_valid_json "no-subagents - valid JSON" "$result"
assert_field "no-subagents - status PASS" "$result" ".status" "PASS"

# Test: no hooks at all → PASS (nothing to inherit)
result=$(SENTINEL_SETTINGS_FILE="$FIXTURES/no-hooks-subagent/settings.json" \
  SENTINEL_PROJECT_DIR="$FIXTURES/no-settings" \
  sh "$CHECK")
assert_valid_json "no-hooks - valid JSON" "$result"
assert_field "no-hooks - status PASS" "$result" ".status" "PASS"

# Test: neither settings file exists → SKIP
result=$(SENTINEL_SETTINGS_FILE="$FIXTURES/no-settings/settings.json" \
  SENTINEL_PROJECT_DIR="$FIXTURES/no-settings" \
  sh "$CHECK")
assert_valid_json "no-settings - valid JSON" "$result"
assert_field "no-settings - status SKIP" "$result" ".status" "SKIP"

printf '\n%d passed, %d failed\n' "$passed" "$failed"
[ "$failed" -eq 0 ] || exit 1
