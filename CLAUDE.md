# CLAUDE.md

## Project Overview

**redhat-status** is a GitHub Action that checks Red Hat service health via the Statuspage.io v2 API at `status.redhat.com`. It reports degraded services and unresolved incidents, with optional component filtering and fail-on-outage behavior.

## Commands

```bash
make lint       # Check scripts with shellcheck + shfmt
make fix-lint   # Auto-fix shfmt formatting
make help       # Show available targets
```

## Architecture

Simple composite action: `action.yml` delegates to a single script `scripts/check-status.sh`.

### API Endpoints

- `/api/v2/status.json` — overall indicator (`none`/`minor`/`major`/`critical`)
- `/api/v2/components.json` — flat array; groups have `"group": true`, children have `group_id`
- `/api/v2/incidents/unresolved.json` — active incidents with `impact`, `name`, `shortlink`

### Key Patterns

- `jq` for all JSON parsing (pre-installed on GitHub Actions runners)
- Retry logic: 3 attempts with exponential backoff (2/4/8s)
- Outputs via `$GITHUB_OUTPUT`, markdown summary via `$GITHUB_STEP_SUMMARY`
- Component filtering: case-insensitive group name matching with unmatched filter warnings

## Shell Standards

- Linting: shellcheck + shfmt (2-space indent, case indentation)
- Strict mode: `set -euo pipefail`

## CI

- `pre-main.yml`: lint (blocks) -> integration test (runs action with defaults + component filter)
- `update-major-tag.yml`: maintains `v0` tag on release

## Release Process

Semantic versioning (v0.0.x). Tag a release and `update-major-tag.yml` updates `v0`.
