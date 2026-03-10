#!/usr/bin/env sh
set -eu
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
CHECK="$SCRIPT_DIR/../../../src/checks/plugins/registry-drift.sh"
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

# Test: installed has extra "c", settings only declares "a","b" → WARN
result=$(SENTINEL_INSTALLED_PLUGINS="$FIXTURES/drift/installed_plugins.json" \
  SENTINEL_SETTINGS_FILE="$FIXTURES/drift/settings.json" \
  sh "$CHECK")
assert_valid_json "drift - valid JSON" "$result"
assert_field "drift - status WARN" "$result" ".status" "WARN"
assert_field "drift - severity medium" "$result" ".severity" "medium"
assert_field "drift - has evidence" "$result" '.evidence | length > 0' "true"

# Test: installed == declared → PASS
result=$(SENTINEL_INSTALLED_PLUGINS="$FIXTURES/match/installed_plugins.json" \
  SENTINEL_SETTINGS_FILE="$FIXTURES/match/settings.json" \
  sh "$CHECK")
assert_valid_json "match - valid JSON" "$result"
assert_field "match - status PASS" "$result" ".status" "PASS"

# Test: installed_plugins.json does not exist → SKIP
result=$(SENTINEL_INSTALLED_PLUGINS="$FIXTURES/empty/installed_plugins.json" \
  SENTINEL_SETTINGS_FILE="$FIXTURES/empty/settings.json" \
  sh "$CHECK")
assert_valid_json "empty - valid JSON" "$result"
assert_field "empty - status SKIP" "$result" ".status" "SKIP"

printf '\n%d passed, %d failed\n' "$passed" "$failed"
[ "$failed" -eq 0 ] || exit 1
