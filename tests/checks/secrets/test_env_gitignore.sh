#!/usr/bin/env sh
set -eu
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
CHECK="$SCRIPT_DIR/../../../src/checks/secrets/env-gitignore.sh"
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

# Test: .env exists AND listed in .gitignore → PASS
result=$(SENTINEL_PROJECT_DIR="$FIXTURES/project-with-gitignore" \
  sh "$CHECK")
assert_valid_json "env in gitignore - valid JSON" "$result"
assert_field "env in gitignore passes" "$result" ".status" "PASS"

# Test: .env exists but NOT in .gitignore → FAIL/high
result=$(SENTINEL_PROJECT_DIR="$FIXTURES/project-missing-entry" \
  sh "$CHECK")
assert_valid_json "env missing from gitignore - valid JSON" "$result"
assert_field "env missing from gitignore fails" "$result" ".status" "FAIL"
assert_field "severity is high" "$result" ".severity" "high"
assert_field "evidence has file entry" "$result" '.evidence[0].type' "file"

# Test: no .gitignore and no .env → SKIP
result=$(SENTINEL_PROJECT_DIR="$FIXTURES/project-no-gitignore" \
  sh "$CHECK")
assert_valid_json "no gitignore no env - valid JSON" "$result"
assert_field "no gitignore no env skips" "$result" ".status" "SKIP"

printf '\n%d passed, %d failed\n' "$passed" "$failed"
[ "$failed" -eq 0 ] || exit 1
