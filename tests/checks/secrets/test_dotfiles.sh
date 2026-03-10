#!/usr/bin/env sh
set -eu
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
CHECK="$SCRIPT_DIR/../../../src/checks/secrets/dotfiles.sh"

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

# Create temp HOME with .zshrc containing a secret
TMPDIR_HOME=$(mktemp -d)
trap 'rm -rf "$TMPDIR_HOME"' EXIT INT TERM

printf '# shell config\nexport OPENAI_API_KEY=sk-test123\nexport PATH="$HOME/.local/bin:$PATH"\n' \
  > "$TMPDIR_HOME/.zshrc"

result=$(HOME="$TMPDIR_HOME" sh "$CHECK")
assert_valid_json "dotfile with secret - valid JSON" "$result"
assert_field "dotfile with secret fails" "$result" ".status" "FAIL"
assert_field "severity is high" "$result" ".severity" "high"
assert_field "evidence is redacted" "$result" '.evidence[0].redacted' "true"
assert_field "evidence type is file" "$result" '.evidence[0].type' "file"

# Test: dotfile with TOKEN secret
printf '# config\nexport GITHUB_TOKEN=ghp_mytoken123\n' > "$TMPDIR_HOME/.bashrc"
result=$(HOME="$TMPDIR_HOME" sh "$CHECK")
assert_valid_json "dotfile with token - valid JSON" "$result"
assert_field "dotfile with token fails" "$result" ".status" "FAIL"

# Test: clean dotfiles (no secrets)
TMPDIR_CLEAN=$(mktemp -d)
trap 'rm -rf "$TMPDIR_HOME" "$TMPDIR_CLEAN"' EXIT INT TERM

printf '# clean shell config\nexport PATH="$HOME/.local/bin:$PATH"\nalias ll="ls -la"\n' \
  > "$TMPDIR_CLEAN/.zshrc"

result=$(HOME="$TMPDIR_CLEAN" sh "$CHECK")
assert_valid_json "clean dotfiles - valid JSON" "$result"
assert_field "clean dotfiles pass" "$result" ".status" "PASS"

# Test: no dotfiles at all → SKIP
TMPDIR_EMPTY=$(mktemp -d)
trap 'rm -rf "$TMPDIR_HOME" "$TMPDIR_CLEAN" "$TMPDIR_EMPTY"' EXIT INT TERM

result=$(HOME="$TMPDIR_EMPTY" sh "$CHECK")
assert_valid_json "no dotfiles - valid JSON" "$result"
assert_field "no dotfiles skips" "$result" ".status" "SKIP"

printf '\n%d passed, %d failed\n' "$passed" "$failed"
[ "$failed" -eq 0 ] || exit 1
