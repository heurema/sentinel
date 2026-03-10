#!/usr/bin/env sh
set -eu
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
CHECK="$SCRIPT_DIR/../../../src/checks/secrets/env-plaintext.sh"
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

# Test: directory with plaintext .env containing API keys → FAIL
result=$(SENTINEL_PROJECT_DIR="$FIXTURES/project-with-secrets" \
SENTINEL_PLATFORM="darwin" \
  sh "$CHECK")
assert_valid_json "detects plaintext secrets - valid JSON" "$result"
assert_field "detects plaintext secrets" "$result" ".status" "FAIL"
assert_field "severity is critical" "$result" ".severity" "critical"
assert_field "evidence redacted" "$result" '.evidence[0].redacted' "true"

# Test: directory with no .env → PASS
result=$(SENTINEL_PROJECT_DIR="$FIXTURES/project-clean" \
SENTINEL_PLATFORM="darwin" \
  sh "$CHECK")
assert_valid_json "clean project - valid JSON" "$result"
assert_field "clean project passes" "$result" ".status" "PASS"

# Test: .env exists but no secrets → PASS
result=$(SENTINEL_PROJECT_DIR="$FIXTURES/project-safe-env" \
SENTINEL_PLATFORM="darwin" \
  sh "$CHECK")
assert_valid_json "safe env - valid JSON" "$result"
assert_field "safe env passes" "$result" ".status" "PASS"

printf '\n%d passed, %d failed\n' "$passed" "$failed"
[ "$failed" -eq 0 ] || exit 1
