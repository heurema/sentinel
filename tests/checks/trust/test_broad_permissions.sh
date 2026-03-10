#!/usr/bin/env sh
set -eu
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
CHECK="$SCRIPT_DIR/../../../src/checks/trust/broad-permissions.sh"
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

# Test: wildcard * in allow → FAIL/high
result=$(SENTINEL_SETTINGS_FILE="$FIXTURES/wildcard/settings.json" sh "$CHECK")
assert_valid_json "wildcard - valid JSON" "$result"
assert_field "wildcard fails" "$result" ".status" "FAIL"
assert_field "wildcard severity" "$result" ".severity" "high"
assert_field "wildcard category" "$result" ".category" "trust"

# Test: Bash(*) in allow → WARN/high
result=$(SENTINEL_SETTINGS_FILE="$FIXTURES/bash-wildcard/settings.json" sh "$CHECK")
assert_valid_json "bash-wildcard - valid JSON" "$result"
assert_field "bash-wildcard warns" "$result" ".status" "WARN"
assert_field "bash-wildcard severity" "$result" ".severity" "high"

# Test: scoped permissions → PASS
result=$(SENTINEL_SETTINGS_FILE="$FIXTURES/scoped/settings.json" sh "$CHECK")
assert_valid_json "scoped - valid JSON" "$result"
assert_field "scoped passes" "$result" ".status" "PASS"

# Test: empty settings (no permissions key) → PASS
result=$(SENTINEL_SETTINGS_FILE="$FIXTURES/default/settings.json" sh "$CHECK")
assert_valid_json "default - valid JSON" "$result"
assert_field "default passes" "$result" ".status" "PASS"

# Test: settings file doesn't exist → SKIP
result=$(SENTINEL_SETTINGS_FILE="/nonexistent/settings.json" sh "$CHECK")
assert_valid_json "missing file - valid JSON" "$result"
assert_field "missing file skips" "$result" ".status" "SKIP"

# Test: no env set → SKIP
result=$(sh "$CHECK")
assert_valid_json "no env - valid JSON" "$result"
assert_field "no env skips" "$result" ".status" "SKIP"

printf '\n%d passed, %d failed\n' "$passed" "$failed"
[ "$failed" -eq 0 ] || exit 1
