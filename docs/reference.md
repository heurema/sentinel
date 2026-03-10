# sentinel reference

## Checks

### secrets

| ID | Severity | What it checks |
|----|----------|----------------|
| `secrets-env-plaintext` | critical | `.env` and `.env.*` files containing API key patterns (`_API_KEY=`, `_SECRET=`, `_TOKEN=`, `_PASSWORD=`, `ANTHROPIC_API`, `OPENAI_API`, `AWS_SECRET`, `GITHUB_TOKEN`) |
| `secrets-env-gitignore` | high | Whether `.env` files are listed in `.gitignore`; a `.env` present but not gitignored is a leak risk |
| `secrets-git-history` | high | Git log for commits that introduced secret patterns; scans `HEAD~50` by default |
| `secrets-runtime-env` | critical | Live process environment (`/proc/*/environ` on Linux, `ps eww` on macOS) for secret-looking variables exported to running processes |
| `secrets-dotfiles` | high | Dotfiles in `$HOME` (`~/.bashrc`, `~/.zshrc`, `~/.profile`, etc.) for hardcoded tokens |

### mcp

| ID | Severity | What it checks |
|----|----------|----------------|
| `mcp-plaintext-creds` | critical | MCP server config (`.mcp.json`, `~/.claude/.mcp.json`) for API keys stored as plaintext strings in the `env` block |
| `mcp-no-allowlist` | medium | Whether MCP servers declare an `allowedTools` list; servers without one have unrestricted tool access |
| `mcp-unpinned-versions` | medium | `npx`/`uvx` MCP servers using `@latest` or no version pin — supply-chain risk |

### plugins

| ID | Severity | What it checks |
|----|----------|----------------|
| `plugins-registry-drift` | medium | Whether installed plugins (from `SENTINEL_INSTALLED_PLUGINS` or `~/.claude/plugins/`) match the entries in `plugin.json`; extra or missing entries indicate drift |
| `plugins-scope-leakage` | high | Plugin manifests declaring broad or dangerous scopes (e.g., `bash:unrestricted`, `fs:write:*`) |
| `plugins-unverified` | medium | Plugins installed from non-registry sources (no `heurema/` prefix, local paths, or unrecognised registries) |

### hooks

| ID | Severity | What it checks |
|----|----------|----------------|
| `hooks-no-pretooluse` | critical | Whether `PreToolUse` hooks cover the four destructive tools: `Bash`, `Write`, `Edit`, `NotebookEdit`; checks both `~/.claude/settings.json` and `.claude/settings.json` |
| `hooks-subagent-gap` | high | Whether hooks are configured in the project settings as well as global settings; hooks defined only globally are not inherited by sub-agents in some Claude Code versions |

### trust

| ID | Severity | What it checks |
|----|----------|----------------|
| `trust-no-claudeignore` | medium | Whether a `.claudeignore` file exists in the project root; without one, all files are readable by the agent |
| `trust-broad-permissions` | high | `allowedTools` in settings files for overly permissive patterns (`Bash.*`, `*`, or shell globs) |
| `trust-injection-surface` | medium | CLAUDE.md and AGENTS.md for prompt-injection patterns: base64 blobs, unusual Unicode, `<script>` tags, `IGNORE PREVIOUS INSTRUCTIONS` variants |

### config

| ID | Severity | What it checks |
|----|----------|----------------|
| `config-insecure-defaults` | medium | Claude Code settings for insecure defaults: `dangerouslyAllowBrowser: true`, `trustAllContent: true`, or `disableSafetyChecks: true` |
| `config-stale-sessions` | low | Session files older than 30 days in `~/.claude/projects/` that may contain cached sensitive context |

---

## Configuration

Optional config file at `~/.sentinel/config.json`. All fields are optional.

```json
{
  "disabled_checks": [],
  "disabled_categories": [],
  "ignore_paths": [],
  "check_timeout_ms": 10000,
  "report_retention_days": 90
}
```

| Field | Type | Default | Description |
|-------|------|---------|-------------|
| `disabled_checks` | `string[]` | `[]` | Check IDs to skip (e.g., `["secrets-git-history"]`) |
| `disabled_categories` | `string[]` | `[]` | Categories to skip entirely (e.g., `["config"]`) |
| `ignore_paths` | `string[]` | `[]` | Glob patterns excluded from file-based checks |
| `check_timeout_ms` | `number` | `10000` | Per-check wall-clock limit in milliseconds |
| `report_retention_days` | `number` | `90` | Reports older than this are pruned on the next run |

---

## Exit codes

| Code | Meaning |
|------|---------|
| 0 | PASS — all checks passed |
| 1 | WARN — warnings present but no hard failures |
| 2 | FAIL — one or more failing checks |
| 3 | UNRELIABLE — too many checks errored or were skipped |
| 4 | ABORTED — registry failed to load or no checks planned |
| 5 | ABORTED — config failed to load |

---

## JSON report schema

Reports are written to `~/.sentinel/reports/<run_id>.json` (mode 600). Top-level structure:

```
{
  schema_version: 1,
  meta: {
    run_id,           // "20260310T143022Z" — ISO date compact + Z
    completed_at,     // ISO 8601 datetime
    sentinel_version,
    registry_hash,    // SHA-256 of registry.json (first 12 chars)
    scoring_version,  // integer, currently 1
    platform,         // "darwin" | "linux"
    hostname,
    scan_roots,       // array of absolute paths
    effective_config, // merged config object
    config_sources    // ordered list of config files loaded
  },
  plan: {
    total,    // checks in registry matching platform
    executed, // checks that produced output
    skipped,  // SKIP + UNSUPPORTED
    excluded  // [{check_id, reason}] — disabled by config
  },
  results: [
    {
      check_id, title, category, status,
      severity,       // present on WARN/FAIL
      finding_id,     // 12-char hex fingerprint
      fingerprint_version,
      duration_ms,
      evidence: [{type, path?, detail, snippet?, redacted?}],
      remediation: {description, argv?, risk}
    }
  ],
  scoring: {
    total,        // 0–100
    by_category   // {secrets: N, mcp: N, ...}
  },
  reliability,          // 0.0–1.0
  reliability_details,  // {scoreable, planned, excluded_statuses}
  verdict,              // "PASS" | "WARN" | "FAIL" | "UNRELIABLE" | "ABORTED"
  verdict_reasons       // [string]
}
```

---

## Environment variables

These variables are available to the sentinel skill and injected into each check script's environment:

| Variable | Default | Description |
|----------|---------|-------------|
| `SENTINEL_PROJECT_DIR` | `.` (cwd) | Root of the project being audited |
| `SENTINEL_PLATFORM` | auto-detected | `darwin` or `linux` |
| `SENTINEL_CLAUDE_HOME` | `~/.claude` | Claude Code home directory |
| `SENTINEL_SETTINGS_FILE` | `~/.claude/settings.json` | Global Claude Code settings path |
| `SENTINEL_PROJECTS_DIR` | `~/.claude/projects` | Claude Code project session cache |
| `SENTINEL_INSTALLED_PLUGINS` | `~/.claude/plugins` | Installed plugin directory |
