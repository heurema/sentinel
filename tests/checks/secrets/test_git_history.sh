#!/usr/bin/env sh
set -eu
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
CHECK="$SCRIPT_DIR/../../../src/checks/secrets/git-history.sh"

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

# Create temp git repo with a committed .env containing secrets → FAIL
TMPDIR_REPO=$(mktemp -d)
trap 'rm -rf "$TMPDIR_REPO"' EXIT INT TERM

cd "$TMPDIR_REPO"
git init -q
git config user.email "test@test.com"
git config user.name "Test"
printf 'OPENAI_API_KEY=sk-secret123\nDB_HOST=localhost\n' > .env
git add .env
git commit -q -m "initial commit"
# Now remove .env so the repo appears clean currently (but history has it)
git rm -q .env
git commit -q -m "remove .env"

result=$(SENTINEL_PROJECT_DIR="$TMPDIR_REPO" sh "$CHECK")
assert_valid_json "git history with secrets - valid JSON" "$result"
assert_field "git history detects secrets" "$result" ".status" "FAIL"
assert_field "severity is high" "$result" ".severity" "high"
assert_field "evidence has runtime entry" "$result" '.evidence[0].type' "runtime"

# Test: git repo with no .env commits → PASS
TMPDIR_CLEAN=$(mktemp -d)
trap 'rm -rf "$TMPDIR_REPO" "$TMPDIR_CLEAN"' EXIT INT TERM

cd "$TMPDIR_CLEAN"
git init -q
git config user.email "test@test.com"
git config user.name "Test"
printf 'hello world\n' > README.md
git add README.md
git commit -q -m "initial"

result=$(SENTINEL_PROJECT_DIR="$TMPDIR_CLEAN" sh "$CHECK")
assert_valid_json "clean git history - valid JSON" "$result"
assert_field "clean git history passes" "$result" ".status" "PASS"

# Test: not a git repo → SKIP
TMPDIR_NOGIT=$(mktemp -d)
trap 'rm -rf "$TMPDIR_REPO" "$TMPDIR_CLEAN" "$TMPDIR_NOGIT"' EXIT INT TERM

result=$(SENTINEL_PROJECT_DIR="$TMPDIR_NOGIT" sh "$CHECK")
assert_valid_json "not a git repo - valid JSON" "$result"
assert_field "not a git repo skips" "$result" ".status" "SKIP"

printf '\n%d passed, %d failed\n' "$passed" "$failed"
[ "$failed" -eq 0 ] || exit 1
