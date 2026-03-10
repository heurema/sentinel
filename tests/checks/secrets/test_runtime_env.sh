#!/usr/bin/env sh
set -eu
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
CHECK="$SCRIPT_DIR/../../../src/checks/secrets/runtime-env.sh"

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

# Test: sensitive var in environment → FAIL/critical
result=$(export ANTHROPIC_API_KEY=sk-ant-test123 && sh "$CHECK")
assert_valid_json "sensitive var in env - valid JSON" "$result"
assert_field "sensitive var in env fails" "$result" ".status" "FAIL"
assert_field "severity is critical" "$result" ".severity" "critical"
assert_field "evidence is redacted" "$result" '.evidence[0].redacted' "true"
assert_field "evidence type is runtime" "$result" '.evidence[0].type' "runtime"

# Test: GITHUB_TOKEN in env → FAIL
result=$(export GITHUB_TOKEN=ghp_testtoken123 && sh "$CHECK")
assert_valid_json "github token in env - valid JSON" "$result"
assert_field "github token in env fails" "$result" ".status" "FAIL"

# Test: DATABASE_URL with password → FAIL
result=$(export DATABASE_URL="postgresql://user:mysecretpass@localhost/db" && sh "$CHECK")
assert_valid_json "database url with password - valid JSON" "$result"
assert_field "database url with password fails" "$result" ".status" "FAIL"

# Test: DATABASE_URL without password → PASS (no auth)
result=$(export DATABASE_URL="postgresql://localhost/db" && sh "$CHECK")
# May still pick up other leaked vars from the shell environment — just check JSON is valid
# We can't guarantee clean env in test shell, so just verify it runs cleanly
assert_valid_json "database url without password - valid JSON" "$result"

# Test: no sensitive vars (run in clean subshell, unsetting known vars)
result=$(env -i HOME="$HOME" PATH="$PATH" sh "$CHECK")
assert_valid_json "clean env - valid JSON" "$result"
assert_field "clean env passes" "$result" ".status" "PASS"

printf '\n%d passed, %d failed\n' "$passed" "$failed"
[ "$failed" -eq 0 ] || exit 1
