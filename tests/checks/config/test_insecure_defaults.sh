#!/usr/bin/env sh
set -eu
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
CHECK="$SCRIPT_DIR/../../../src/checks/config/insecure-defaults.sh"
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

# Test: autoApprove:true → FAIL/medium
result=$(SENTINEL_SETTINGS_FILE="$FIXTURES/insecure/settings.json" sh "$CHECK")
assert_valid_json "insecure - valid JSON" "$result"
assert_field "insecure fails" "$result" ".status" "FAIL"
assert_field "insecure severity" "$result" ".severity" "medium"
assert_field "insecure category" "$result" ".category" "config"

# Test: bypassPermissions:true → FAIL/medium
result=$(SENTINEL_SETTINGS_FILE="$FIXTURES/bypass/settings.json" sh "$CHECK")
assert_valid_json "bypass - valid JSON" "$result"
assert_field "bypass fails" "$result" ".status" "FAIL"
assert_field "bypass severity" "$result" ".severity" "medium"

# Test: scoped permissions only → PASS
result=$(SENTINEL_SETTINGS_FILE="$FIXTURES/secure/settings.json" sh "$CHECK")
assert_valid_json "secure - valid JSON" "$result"
assert_field "secure passes" "$result" ".status" "PASS"

# Test: empty settings → PASS
result=$(SENTINEL_SETTINGS_FILE="$FIXTURES/empty/settings.json" sh "$CHECK")
assert_valid_json "empty - valid JSON" "$result"
assert_field "empty passes" "$result" ".status" "PASS"

# Test: settings file doesn't exist → SKIP
result=$(SENTINEL_SETTINGS_FILE="/nonexistent/settings.json" sh "$CHECK")
assert_valid_json "missing file - valid JSON" "$result"
assert_field "missing file skips" "$result" ".status" "SKIP"

# Test: no env set and no default file (use a guaranteed missing path)
result=$(SENTINEL_SETTINGS_FILE="/tmp/__no_such_settings_$$.json" sh "$CHECK")
assert_valid_json "no file - valid JSON" "$result"
assert_field "no file skips" "$result" ".status" "SKIP"

printf '\n%d passed, %d failed\n' "$passed" "$failed"
[ "$failed" -eq 0 ] || exit 1
