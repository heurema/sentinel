# Check authoring contract

## What a check is

A check is a POSIX sh script that:

1. Sources `emit.sh` from `$SCRIPT_DIR/../../lib/emit.sh`
2. Performs its inspection
3. Outputs **exactly one JSON line** to stdout using the `emit_*` helpers
4. Exits 0 under normal conditions

The runner captures stdout as the result. Anything written to stderr is logged but does not affect the result. If a check exits non-zero, the runner generates a synthetic `ERROR` result for that check.

## Required structure

```sh
#!/usr/bin/env sh
set -eu

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
. "$SCRIPT_DIR/../../lib/emit.sh"

CHECK_ID="<category>-<name>"
TITLE="Human-readable title"
CATEGORY="<category>"

# ... inspection logic ...

emit_pass "$CHECK_ID" "$TITLE" "$CATEGORY"   # or emit_fail / emit_warn / emit_skip
```

## emit.sh helpers

| Function | Signature | Use when |
|----------|-----------|----------|
| `emit_pass` | `<id> <title> <category>` | Check found no issues |
| `emit_warn` | `<id> <title> <category> <severity> <evidence_json> <remediation_json>` | Issue found but not blocking |
| `emit_fail` | `<id> <title> <category> <severity> <evidence_json> <remediation_json>` | Issue found and blocking |
| `emit_skip` | `<id> <title> <category>` | Precondition not met (e.g., no .env file exists) |
| `emit_unsupported` | `<id> <title> <category> <reason>` | Platform or dependency missing |

Every check **must** handle PASS, FAIL, and at least one of SKIP or UNSUPPORTED. An unconditional `emit_fail` with no condition is not valid.

## Environment variables

All variables are exported by the runner before the check script starts:

| Variable | Description |
|----------|-------------|
| `SENTINEL_PROJECT_DIR` | Root of the project being audited |
| `SENTINEL_PLATFORM` | `darwin` or `linux` |
| `SENTINEL_CLAUDE_HOME` | Claude Code home (default `~/.claude`) |
| `SENTINEL_SETTINGS_FILE` | Path to global `settings.json` |
| `SENTINEL_PROJECTS_DIR` | Claude Code project session cache directory |
| `SENTINEL_INSTALLED_PLUGINS` | Installed plugin directory |
| `SENTINEL_LIB` | Absolute path to `src/lib/` — use to source shared helpers |

## Status and severity matrix

| Status | Severity required? | Score contribution | Included in reliability denominator |
|--------|-------------------|-------------------|--------------------------------------|
| PASS | No | 100 | Yes |
| WARN | Yes | 50 | Yes |
| FAIL | Yes | 0 | Yes |
| SKIP | No | — | No |
| UNSUPPORTED | No | — | No |
| ERROR (synthetic) | No | — | No |

SKIP means the check is not applicable (e.g., no git repo found). UNSUPPORTED means a required tool is absent (e.g., no `jq`). Both reduce reliability.

Valid severity values: `critical`, `high`, `medium`, `low`.

## Evidence rules

Evidence is a JSON array of objects. Each object must have `type` and `detail`:

```json
{
  "type": "file",
  "path": "/abs/path/to/.env",
  "detail": "Contains API_KEY=sk-ab***",
  "redacted": true
}
```

| Field | Type | Rules |
|-------|------|-------|
| `type` | string | One of: `file`, `config`, `runtime`, `process` |
| `path` | string | Absolute path; omit if not file-based |
| `detail` | string | Max 500 characters; must redact secrets |
| `snippet` | string | Optional; max 256 characters |
| `redacted` | boolean | Set to `true` whenever any secret value appears in `detail` or `snippet` |

Use the `redact <value>` helper from `emit.sh` to replace secret values. It preserves the first 4 characters and appends `***`.

**Never include a full secret value in evidence.** Evidence is stored in the report file, which may be shared for debugging.

## Remediation object

```json
{
  "description": "Encrypt .env files with sops+age",
  "argv": ["sops", "-e", "--input-type", "dotenv", ".env"],
  "risk": "caution"
}
```

| Field | Required | Values |
|-------|----------|--------|
| `description` | Yes | Plain English, one sentence |
| `argv` | No | Command as array (used by `sentinel-fix` for safe execution) |
| `risk` | Yes | `safe` — read-only; `caution` — modifies files; `dangerous` — destructive or irreversible |

## Check exit codes

| Exit code | Meaning |
|-----------|---------|
| 0 | Normal — runner uses stdout JSON as result |
| Non-zero | Abnormal — runner generates a synthetic `ERROR` result; stderr is captured as the error detail |

A check must not call `exit 0` before emitting its result. It may call `exit 1` to signal an unexpected failure. The runner does not retry.

## Timeouts

The runner enforces `check_timeout_ms` (default 10 000 ms) per check using a background process + kill. A timed-out check generates a synthetic `ERROR` result with detail `"timeout after Nms"`. Design checks to complete well within the limit; use `head -N` and `find ... | head` to bound filesystem traversal.

## File naming

Scripts must be placed at `src/checks/<category>/<name>.sh` and match the `file` field in `registry.json`. The script must be executable (`chmod +x`).
