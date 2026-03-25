```
                    __  _            __
   ________  ____  / /_(_)___  ___  / /
  / ___/ _ \/ __ \/ __/ / __ \/ _ \/ /
 (__  )  __/ / / / /_/ / / / /  __/ /
/____/\___/_/ /_/\__/_/_/ /_/\___/_/
```

**AI workstation security audit.**

[![Version](https://img.shields.io/badge/version-0.1.0-5b21b6?style=flat-square)](https://github.com/heurema/sentinel)
[![License: MIT](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)

> Deterministic checks for secrets exposure, MCP trust, plugin permissions, hook coverage, trust boundaries, and configuration hygiene.

---

## Install

<!-- INSTALL:START -->
```bash
claude plugin add heurema/sentinel
```
<!-- INSTALL:END -->

## Quick start

```
/sentinel              # Run full security audit
/sentinel --deep       # Audit + LLM risk explanation
/sentinel-fix <run_id> # Guided remediation walkthrough
/sentinel-diff         # Compare with previous audit
```

## Commands

| Command | Description |
|---------|-------------|
| `/sentinel` | Run full security audit with terminal scorecard |
| `/sentinel --deep` | Audit with LLM risk explanation |
| `/sentinel-fix <run_id>` | Guided remediation for audit findings |
| `/sentinel-diff` | Compare current audit with previous run |

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

## See also

- [How it works](docs/how-it-works.md)
- [Reference](docs/reference.md)
- [Check contract](docs/check-contract.md)
- [Adding checks](docs/adding-checks.md)

## License

MIT
