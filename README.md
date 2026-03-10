# sentinel

AI Workstation Security Audit — deterministic checks for secrets exposure, MCP trust, plugin permissions, hook coverage, trust boundaries, and configuration hygiene.

## Installation

<!-- INSTALL:START -->
```bash
claude plugin add heurema/sentinel
```
<!-- INSTALL:END -->

## Quick Start

```
/sentinel              # Run full security audit
/sentinel --deep       # Audit + LLM risk explanation
/sentinel-fix <run_id> # Guided remediation walkthrough
/sentinel-diff         # Compare with previous audit
```

## Features

- 18 deterministic security checks across 6 categories
- JSON-canonical reports with terminal scorecard
- Scored security posture (0-100) with hard-gate verdicts
- Guided remediation with safe/caution/dangerous risk badges
- Report diffing with finding-level change tracking
- SessionStart hook for stale audit reminders

## Categories

| Category | Checks | Focus |
|----------|--------|-------|
| secrets | 5 | Plaintext API keys, env exposure, git history, dotfiles |
| mcp | 3 | Plaintext credentials, missing allowlists, unpinned versions |
| plugins | 3 | Registry drift, scope leakage, unverified plugins |
| hooks | 2 | Missing PreToolUse guards, subagent hook gap |
| trust | 3 | Missing .claudeignore, broad permissions, injection surface |
| config | 2 | Insecure defaults, stale sessions |

## Configuration

Optional `~/.sentinel/config.json`:

```json
{
  "disabled_checks": [],
  "disabled_categories": [],
  "ignore_paths": [],
  "check_timeout_ms": 10000,
  "report_retention_days": 90
}
```

## Privacy

- Reports stored locally at `~/.sentinel/reports/` with 600 permissions
- Secrets in evidence are always redacted
- `--deep` mode sends aggregate findings (no raw secrets) to the LLM
- No network calls during base audit

## See Also

- [How it works](docs/how-it-works.md)
- [Check contract](docs/check-contract.md)
- [Adding checks](docs/adding-checks.md)

## License

MIT
