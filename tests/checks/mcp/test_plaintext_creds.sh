#!/usr/bin/env sh
set -eu
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
CHECK="$SCRIPT_DIR/../../../src/checks/mcp/plaintext-creds.sh"
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

# Test: .mcp.json with plaintext sk- credential → FAIL
result=$(SENTINEL_PROJECT_DIR="$FIXTURES/project-with-creds" \
  SENTINEL_CLAUDE_HOME="$FIXTURES/no-such-dir" \
  sh "$CHECK")
assert_valid_json "plaintext creds - valid JSON" "$result"
assert_field "plaintext creds - status FAIL" "$result" ".status" "FAIL"
assert_field "plaintext creds - severity critical" "$result" ".severity" "critical"
assert_field "plaintext creds - evidence redacted" "$result" '.evidence[0].redacted' "true"
assert_field "plaintext creds - evidence has server" "$result" '.evidence[0].detail' "test.API_KEY=sk-a***"

# Test: .mcp.json with $VAR references → PASS
result=$(SENTINEL_PROJECT_DIR="$FIXTURES/project-safe" \
  SENTINEL_CLAUDE_HOME="$FIXTURES/no-such-dir" \
  sh "$CHECK")
assert_valid_json "safe project - valid JSON" "$result"
assert_field "safe project - status PASS" "$result" ".status" "PASS"

# Test: no .mcp.json → SKIP
result=$(SENTINEL_PROJECT_DIR="$FIXTURES/project-no-mcp" \
  SENTINEL_CLAUDE_HOME="$FIXTURES/no-such-dir" \
  sh "$CHECK")
assert_valid_json "no mcp - valid JSON" "$result"
assert_field "no mcp - status SKIP" "$result" ".status" "SKIP"

printf '\n%d passed, %d failed\n' "$passed" "$failed"
[ "$failed" -eq 0 ] || exit 1
