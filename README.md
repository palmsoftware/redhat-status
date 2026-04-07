# redhat-status

[![Test Changes](https://github.com/palmsoftware/redhat-status/actions/workflows/pre-main.yml/badge.svg)](https://github.com/palmsoftware/redhat-status/actions/workflows/pre-main.yml)

A GitHub Action that checks [Red Hat service health](https://status.redhat.com/) and reports any outages or degraded services. Useful as a pre-flight check before workflows that depend on Red Hat infrastructure (OpenShift, Quay.io, RHEL, etc.).

## Usage

### Basic

```yaml
- name: Check Red Hat Status
  uses: palmsoftware/redhat-status@v0
```

### Fail on outage

```yaml
- name: Check Red Hat Status
  uses: palmsoftware/redhat-status@v0
  with:
    fail-on-outage: 'true'
```

### Filter to specific component groups

```yaml
- name: Check Red Hat Status
  id: rh-status
  uses: palmsoftware/redhat-status@v0
  with:
    components: |
      api.openshift.com
      Quay.io

- name: React to outage
  if: steps.rh-status.outputs.is-outage == 'true'
  run: echo "Red Hat services are degraded!"
```

## Inputs

| Input | Description | Required | Default |
|-------|-------------|----------|---------|
| `fail-on-outage` | Fail the workflow step if Red Hat status is not fully operational | No | `false` |
| `components` | Newline-separated list of component group names to filter on | No | _(all)_ |

## Outputs

| Output | Description | Example |
|--------|-------------|---------|
| `status` | Overall status indicator | `none`, `minor`, `major`, `critical` |
| `is-outage` | Whether any outage is detected | `true`, `false` |
| `degraded-count` | Number of non-operational components | `3` |
| `incident-count` | Number of unresolved incidents | `1` |

## Step Summary

When run in GitHub Actions, the action writes a markdown summary to the workflow run with:
- Overall status with emoji indicators
- Table of affected components (if any)
- Table of active incidents with impact levels and links

## Component Groups

Component group names for the `components` filter can be found on [status.redhat.com](https://status.redhat.com/). Examples include:
- `api.openshift.com`
- `Quay.io`
- `Container Registries`
- `console.redhat.com`
- `developers.redhat.com`
- `docs.redhat.com`

## License

Apache License 2.0 — see [LICENSE](LICENSE).
