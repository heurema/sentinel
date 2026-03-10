#!/usr/bin/env sh
set -eu
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
CHECK="$SCRIPT_DIR/../../../src/checks/trust/no-claudeignore.sh"
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

# Test: project with .claudeignore → PASS
result=$(SENTINEL_PROJECT_DIR="$FIXTURES/project-with-claudeignore" sh "$CHECK")
assert_valid_json "with-claudeignore - valid JSON" "$result"
assert_field "with-claudeignore passes" "$result" ".status" "PASS"
assert_field "with-claudeignore category" "$result" ".category" "trust"

# Test: project without .claudeignore → FAIL/medium
result=$(SENTINEL_PROJECT_DIR="$FIXTURES/project-without-claudeignore" sh "$CHECK")
assert_valid_json "without-claudeignore - valid JSON" "$result"
assert_field "without-claudeignore fails" "$result" ".status" "FAIL"
assert_field "without-claudeignore severity" "$result" ".severity" "medium"
assert_field "without-claudeignore category" "$result" ".category" "trust"

# Test: SENTINEL_PROJECT_DIR not set → SKIP
result=$(sh "$CHECK")
assert_valid_json "no env - valid JSON" "$result"
assert_field "no env skips" "$result" ".status" "SKIP"

# Test: SENTINEL_PROJECT_DIR is not a directory → SKIP
result=$(SENTINEL_PROJECT_DIR="/nonexistent/path" sh "$CHECK")
assert_valid_json "nonexistent dir - valid JSON" "$result"
assert_field "nonexistent dir skips" "$result" ".status" "SKIP"

# Test: remediation argv is touch .claudeignore
result=$(SENTINEL_PROJECT_DIR="$FIXTURES/project-without-claudeignore" sh "$CHECK")
assert_field "remediation argv[0]" "$result" ".remediation.argv[0]" "touch"
assert_field "remediation argv[1]" "$result" ".remediation.argv[1]" ".claudeignore"
assert_field "remediation risk" "$result" ".remediation.risk" "safe"

printf '\n%d passed, %d failed\n' "$passed" "$failed"
[ "$failed" -eq 0 ] || exit 1
