# Security policy

## Reporting a vulnerability

Report security issues via [GitHub Security Advisories](https://github.com/heurema/sentinel/security/advisories/new). Do not open a public issue.

Include:
- A description of the vulnerability
- Steps to reproduce
- Potential impact
- Affected versions (check `plugin.json` for the current version)

You will receive an acknowledgement within 48 hours and a resolution timeline within 5 business days.

## Sensitive information in reports

Sentinel reports (`~/.sentinel/reports/*.json`) contain:

- File paths to configuration and credential files
- Redacted secret values (first 4 characters + `***`)
- Hook and permission configurations
- Installed plugin lists

Although secrets are redacted, the reports contain enough context (file paths, key names, configuration structure) to help an attacker understand the system layout.

**Never share a sentinel report publicly without manual review.** Before sharing for debugging, verify that:

1. All `evidence[].path` values are paths you are comfortable disclosing
2. All `evidence[].detail` fields contain only redacted values (`***`)
3. The report does not reveal the presence of sensitive files you wish to keep private

## Scope

Sentinel is a **detection tool, not a prevention tool**. It reads configuration files and scans for known patterns; it does not modify, block, or quarantine anything. Sentinel itself cannot prevent a secret from being leaked — it can only report that one exists.

Fix recommendations in `sentinel-fix` are advisory. The `argv` field in each remediation object is shown to the LLM for explanation; no command is executed without explicit user confirmation.

## Data handling

- All reports are stored locally at `~/.sentinel/reports/` with mode 600
- No data is sent to any network endpoint during a base audit
- In `--deep` mode, aggregate findings (check IDs, statuses, severities, and non-path evidence) are sent to the active LLM. Raw file paths and secret fragments are excluded from the `--deep` payload

## Known limitations

- Git history scanning (`secrets-git-history`) checks only the last 50 commits; older leaked secrets are not detected
- Runtime environment scanning may miss secrets in short-lived processes
- Checks run as the current user; files readable only by root or other users are not inspected
