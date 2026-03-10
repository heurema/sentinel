# Adding a new check

This guide walks through adding a check from scratch. The example adds `trust-writable-settings` — a check that warns when `~/.claude/settings.json` is world-writable.

## 1. Create the script

Create `src/checks/<category>/<name>.sh`. Use the category and name that will form the check ID.

```sh
#!/usr/bin/env sh
# trust-writable-settings: Warn when settings.json is writable by group or other
set -eu

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
. "$SCRIPT_DIR/../../lib/emit.sh"

CHECK_ID="trust-writable-settings"
TITLE="settings.json is world- or group-writable"
CATEGORY="trust"

SETTINGS="${SENTINEL_SETTINGS_FILE:-$HOME/.claude/settings.json}"

if [ ! -f "$SETTINGS" ]; then
  emit_skip "$CHECK_ID" "$TITLE" "$CATEGORY"
  exit 0
fi

# Check for group-write (g+w) or other-write (o+w)
perms=$(ls -la "$SETTINGS" | awk '{print $1}')
if printf '%s' "$perms" | grep -qE '..(w|..w)'; then
  evidence=$(jq -n --arg p "$SETTINGS" --arg d "Permissions: $perms" \
    '[{"type":"file","path":$p,"detail":$d}]')
  emit_fail "$CHECK_ID" "$TITLE" "$CATEGORY" "high" \
    "$evidence" \
    '{"description":"Restrict settings.json to owner-read-write only","argv":["chmod","600","~/.claude/settings.json"],"risk":"safe"}'
else
  emit_pass "$CHECK_ID" "$TITLE" "$CATEGORY"
fi
```

Make the script executable:

```bash
chmod +x src/checks/trust/writable-settings.sh
```

## 2. Add an entry to registry.json

Open `src/checks/registry.json` and append an entry to the array:

```json
{
  "id": "trust-writable-settings",
  "file": "trust/writable-settings.sh",
  "category": "trust",
  "severity_default": "high",
  "weight": 8,
  "timeout_ms": 5000,
  "optional": false,
  "platforms": ["darwin", "linux"],
  "default_enabled": true
}
```

Field notes:
- `id` must be unique and match `<category>-<name>` exactly
- `file` is relative to `src/checks/`
- `weight` follows the convention: critical → 10, high → 8, medium → 5, low → 3
- `timeout_ms` — keep short for filesystem checks (5 000 ms); longer for git history scans (30 000 ms)

## 3. Create the test file

Create `tests/checks/<category>/test_<name>.sh`:

```sh
#!/usr/bin/env sh
# Tests for trust-writable-settings
set -eu

CHECKS_DIR="$(cd "$(dirname "$0")/../../.." && pwd)/src/checks"
FIXTURES="$(cd "$(dirname "$0")" && pwd)/fixtures/trust-writable-settings"

. "$(dirname "$0")/../../helpers/assert.sh"

# --- Test: PASS when permissions are 600 ---
_f="$FIXTURES/settings-600.json"
result=$(SENTINEL_SETTINGS_FILE="$_f" sh "$CHECKS_DIR/trust/writable-settings.sh")
assert_status "$result" "PASS"

# --- Test: FAIL when permissions are 664 ---
_f="$FIXTURES/settings-664.json"
chmod 664 "$_f"
result=$(SENTINEL_SETTINGS_FILE="$_f" sh "$CHECKS_DIR/trust/writable-settings.sh")
assert_status "$result" "FAIL"
assert_field "$result" ".severity" "high"
assert_redacted "$result"

# --- Test: SKIP when file absent ---
result=$(SENTINEL_SETTINGS_FILE="/nonexistent/settings.json" sh "$CHECKS_DIR/trust/writable-settings.sh")
assert_status "$result" "SKIP"
```

## 4. Create fixtures

Put minimal fixture files under `tests/checks/<category>/fixtures/<check-id>/`:

```
tests/checks/trust/fixtures/trust-writable-settings/
  settings-600.json   # valid settings, permissions will be set by test setup
  settings-664.json   # same content, chmod 664 applied in test
```

Fixture content can be minimal — just enough for the check to parse:

```json
{}
```

Fixture files with secrets must be redacted. Never commit real API keys or tokens in fixtures.

## 5. Run the test and verify

```bash
# Run just your new test
sh tests/checks/trust/test_writable-settings.sh

# Run the full suite
sh tests/run.sh

# Validate registry.json is still valid and IDs are unique
jq '.[].id' src/checks/registry.json | sort | uniq -d   # should print nothing
```

Expected output from a passing test:

```
PASS  trust-writable-settings: PASS when permissions are 600
PASS  trust-writable-settings: FAIL when permissions are 664
PASS  trust-writable-settings: SKIP when file absent
3 tests passed, 0 failed
```

## Checklist

Before opening a PR:

- [ ] Script is executable (`chmod +x`)
- [ ] Script exits 0 under all normal paths
- [ ] All evidence `detail` fields are under 500 characters
- [ ] All secret values are redacted via `redact()`
- [ ] `emit_pass`, `emit_fail` (or `emit_warn`), and `emit_skip`/`emit_unsupported` are all reachable
- [ ] Registry entry added with correct `id`, `file`, `category`, `weight`
- [ ] Test covers PASS, FAIL, and SKIP/UNSUPPORTED
- [ ] Fixtures contain no real secrets
- [ ] `jq '.[].id' src/checks/registry.json | sort | uniq -d` prints nothing
