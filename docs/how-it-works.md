# How sentinel works

## Pipeline stages

Each `/sentinel` run executes a fixed nine-stage pipeline:

```
LOAD → VALIDATE → PLAN → RUN → NORMALIZE → ASSESS → PERSIST → RENDER → ADVISE
```

| Stage | Library | What happens |
|-------|---------|--------------|
| LOAD | `runner.sh` | Reads `registry.json` and `~/.sentinel/config.json` into memory; hard-exits on malformed JSON |
| VALIDATE | `runner.sh` | Checks for duplicate IDs; warns (non-fatal) on missing or non-executable scripts |
| PLAN | `runner.sh` | Filters the registry by `disabled_checks`, `disabled_categories`, and platform; builds the ordered execution list |
| RUN | `runner.sh` | Runs each check script in isolation; captures stdout (one JSON line); enforces `check_timeout_ms`; wraps non-zero exits as synthetic `ERROR` results |
| NORMALIZE | `scorer.sh` | Augments each result with `finding_id` (12-char SHA-256 of `check_id|category|sorted_evidence_paths`) and `duration_ms`; status is excluded from the hash so a finding keeps its ID across PASS↔FAIL transitions |
| ASSESS | `scorer.sh` | Computes per-category and total scores; derives `reliability`; selects `verdict` |
| PERSIST | `reporter.sh` | Assembles the full report JSON and writes it atomically to `~/.sentinel/reports/<run_id>.json` with mode 600 |
| RENDER | `reporter.sh` | Prints a terminal scorecard with ANSI colour, per-category rows, and finding summaries |
| ADVISE | skill | In `--deep` mode only: sends aggregate findings (no raw secrets) to the LLM for risk explanation |

## Check registry

Checks are discovered from `src/checks/registry.json` — a JSON array of objects. Each entry specifies:

- `id` — unique kebab-case identifier (`<category>-<name>`)
- `file` — path relative to `src/checks/`
- `category` — one of `secrets`, `mcp`, `plugins`, `hooks`, `trust`, `config`
- `severity_default` — `critical | high | medium | low`
- `weight` — integer used in scoring (see below)
- `timeout_ms` — per-check wall-clock limit (overridden by `check_timeout_ms` config)
- `platforms` — `["darwin"]`, `["linux"]`, or both
- `default_enabled` — `true | false`

At LOAD time the full registry is read. At PLAN time, checks are filtered to those matching the current platform, not in `disabled_checks`, and not in `disabled_categories`. The resulting ordered list is the *plan*.

## Scoring model

### Per-check status values

| Status | Score contribution |
|--------|-------------------|
| PASS | 100 |
| WARN | 50 |
| FAIL | 0 |
| ERROR | excluded |
| SKIP | excluded |
| UNSUPPORTED | excluded |

### Per-category score

Each category score is the weighted average of its scoreable checks:

```
category_score = sum(check_score * check_weight) / sum(check_weight)
                 for checks with status in {PASS, WARN, FAIL}
```

### Total score

The total is a weighted average across categories:

```
total_score = sum(category_score * category_weight) / sum(category_weight)
```

Category weights:

| Category | Weight |
|----------|--------|
| secrets | 1.5 |
| trust | 1.5 |
| hooks | 1.2 |
| mcp | 1.0 |
| plugins | 1.0 |
| config | 1.0 |

### Reliability

Reliability measures audit health, independent of security posture:

```
reliability = scoreable_count / planned_count
```

Checks in ERROR, SKIP, or UNSUPPORTED status reduce reliability. A run with all checks excluded has reliability = 0.

### Verdict gates

Verdicts are evaluated in order; the first match wins:

| Verdict | Condition |
|---------|-----------|
| ABORTED | `planned_count == 0` or all checks excluded |
| UNRELIABLE | `reliability < 0.7` |
| FAIL | any `critical` or `high` FAIL exists, OR `total_score < 50` |
| WARN | `total_score < 80`, OR any `medium` FAIL exists |
| PASS | default |

### Dual metrics

Sentinel produces two independent metrics:

- **score** (0–100): security posture — how well the workstation is hardened
- **reliability** (0.0–1.0): audit health — how much of the planned audit actually ran

A score of 95 with reliability of 0.4 means the run is not trustworthy. Both must be healthy for a PASS verdict.

## Finding identity

Each normalized result carries a `finding_id`: the first 12 hex characters of SHA-256 over `check_id|category|sorted_evidence_paths`. Because status is excluded from the hash, the same misconfiguration tracked across multiple runs keeps the same `finding_id`, enabling `sentinel-diff` to correlate new, resolved, and changed findings.
