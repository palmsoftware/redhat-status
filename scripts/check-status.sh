#!/usr/bin/env bash
set -euo pipefail

# Check Red Hat service health via the Statuspage.io v2 API
# https://status.redhat.com/

BASE_URL="https://status.redhat.com/api/v2"
FAIL_ON_OUTAGE="${INPUT_FAIL_ON_OUTAGE:-false}"
COMPONENTS_FILTER="${INPUT_COMPONENTS:-}"

# Fetch a URL with retry logic (3 attempts, exponential backoff)
api_fetch() {
  local url="$1"
  local attempt=1
  local max_attempts=3
  local delay=2
  local response

  while [ "$attempt" -le "$max_attempts" ]; do
    if response=$(curl -sf --max-time 10 "$url" 2>/dev/null); then
      echo "$response"
      return 0
    fi
    if [ "$attempt" -lt "$max_attempts" ]; then
      echo "::warning::Attempt $attempt/$max_attempts failed for $url, retrying in ${delay}s..." >&2
      sleep "$delay"
      delay=$((delay * 2))
    fi
    attempt=$((attempt + 1))
  done

  echo "::error::Failed to fetch $url after $max_attempts attempts" >&2
  return 1
}

echo "🔍 Checking Red Hat service status..."
echo ""

# Fetch all three endpoints
status_json=$(api_fetch "${BASE_URL}/status.json") || {
  echo "⚠️  Unable to reach Red Hat status API"
  echo "   Proceeding without status check"
  # Set safe defaults for outputs
  if [ -n "${GITHUB_OUTPUT:-}" ]; then
    {
      echo "status=unknown"
      echo "is-outage=false"
      echo "degraded-count=0"
      echo "incident-count=0"
    } >>"$GITHUB_OUTPUT"
  fi
  exit 0
}

components_json=$(api_fetch "${BASE_URL}/components.json") || components_json='{"components":[]}'
incidents_json=$(api_fetch "${BASE_URL}/incidents/unresolved.json") || incidents_json='{"incidents":[]}'

# Parse overall status
indicator=$(echo "$status_json" | jq -r '.status.indicator')
description=$(echo "$status_json" | jq -r '.status.description')

# Build group ID to name map and find non-operational components
# Groups have "group": true, leaf components have "group": false with a group_id
group_map=$(echo "$components_json" | jq -r '
  [.components[] | select(.group == true)] | map({(.id): .name}) | add // {}
')

# Get non-operational leaf components with their group names
degraded_components=$(echo "$components_json" | jq --argjson groups "$group_map" '
  [.components[]
    | select(.group == false and .status != "operational")
    | {name, status, group_name: ($groups[.group_id] // "Ungrouped")}]
')

# Apply component group filter if specified
if [ -n "$COMPONENTS_FILTER" ]; then
  # Convert newline-separated filter to JSON array (case-insensitive)
  filter_array=$(echo "$COMPONENTS_FILTER" | jq -R -s '
    split("\n") | map(select(length > 0) | ascii_downcase)
  ')

  # Warn about filter names that match zero groups
  echo "$filter_array" | jq -r --argjson groups "$group_map" '
    ($groups | to_entries | map(.value | ascii_downcase)) as $group_names |
    .[] | select(. as $f | $group_names | index($f) | not)
  ' | while IFS= read -r unmatched; do
    echo "::warning::Component group filter '${unmatched}' did not match any groups"
  done

  # Filter degraded components to only matching groups
  degraded_components=$(echo "$degraded_components" | jq --argjson filter "$filter_array" '
    [.[] | select(.group_name | ascii_downcase | IN($filter[]))]
  ')

  # Filter incidents to only those affecting matching component groups
  incidents_json=$(echo "$incidents_json" | jq --argjson filter "$filter_array" --argjson groups "$group_map" '
    .incidents |= [.[]
      | select(.components as $comps |
          ($comps // []) | any(
            .group_id as $gid |
            ($groups[$gid] // "") | ascii_downcase | IN($filter[])
          )
        )
    ]
  ')
fi

degraded_count=$(echo "$degraded_components" | jq 'length')
incident_count=$(echo "$incidents_json" | jq '.incidents | length')

# Determine outage status
is_outage="false"
if [ "$indicator" != "none" ]; then
  is_outage="true"
fi

# Set GitHub Action outputs
if [ -n "${GITHUB_OUTPUT:-}" ]; then
  {
    echo "status=${indicator}"
    echo "is-outage=${is_outage}"
    echo "degraded-count=${degraded_count}"
    echo "incident-count=${incident_count}"
  } >>"$GITHUB_OUTPUT"
fi

# Print console summary
case "$indicator" in
  "none")
    echo "✅ Red Hat Status: All Systems Operational"
    ;;
  "minor")
    echo "⚠️  Red Hat Status: Minor Service Degradation"
    echo "   Description: $description"
    ;;
  "major")
    echo "🔴 Red Hat Status: Major Service Outage"
    echo "   Description: $description"
    ;;
  "critical")
    echo "🔴 Red Hat Status: Critical Service Outage"
    echo "   Description: $description"
    ;;
  *)
    echo "ℹ️  Red Hat Status: $description"
    ;;
esac

# List non-operational components
if [ "$degraded_count" -gt 0 ]; then
  echo ""
  echo "   📋 Non-operational components ($degraded_count):"
  echo "$degraded_components" | jq -r '
    .[] | "   \(
      if .status == "major_outage" then "🔴"
      elif .status == "partial_outage" then "🟠"
      elif .status == "degraded_performance" then "🟡"
      elif .status == "under_maintenance" then "🔧"
      else "⚪"
      end
    ) [\(.group_name)] \(.name) — \(.status | gsub("_"; " "))"
  '
fi

# List unresolved incidents
if [ "$incident_count" -gt 0 ]; then
  echo ""
  echo "   🚨 Unresolved incidents ($incident_count):"
  echo "$incidents_json" | jq -r '
    .incidents[] | "   \(
      if .impact == "critical" then "🔴"
      elif .impact == "major" then "🟠"
      else "🟡"
      end
    ) [\(.impact)] \(.name)\(if .shortlink then " (\(.shortlink))" else "" end)"
  '
fi

echo ""

# Write GitHub Step Summary
if [ -n "${GITHUB_STEP_SUMMARY:-}" ]; then
  {
    case "$indicator" in
      "none") echo "## ✅ Red Hat Service Status" ;;
      "minor") echo "## ⚠️ Red Hat Service Status" ;;
      *) echo "## 🔴 Red Hat Service Status" ;;
    esac

    echo ""
    echo "| Metric | Value |"
    echo "|--------|-------|"
    echo "| Overall Status | \`${indicator}\` — ${description} |"
    echo "| Non-operational Components | ${degraded_count} |"
    echo "| Unresolved Incidents | ${incident_count} |"

    if [ "$degraded_count" -gt 0 ]; then
      echo ""
      echo "### Affected Components"
      echo ""
      echo "| Component | Group | Status |"
      echo "|-----------|-------|--------|"
      echo "$degraded_components" | jq -r '
        .[] | "| \(.name) | \(.group_name) | \(.status | gsub("_"; " ")) |"
      '
    fi

    if [ "$incident_count" -gt 0 ]; then
      echo ""
      echo "### Active Incidents"
      echo ""
      echo "| Incident | Impact | Link |"
      echo "|----------|--------|------|"
      echo "$incidents_json" | jq -r '
        .incidents[] | "| \(.name) | \(.impact) | \(if .shortlink then "[\(.shortlink)](\(.shortlink))" else "—" end) |"
      '
    fi
  } >>"$GITHUB_STEP_SUMMARY"
fi

# Conditional failure
if [ "$FAIL_ON_OUTAGE" = "true" ] && [ "$indicator" != "none" ]; then
  echo "❌ Failing workflow: Red Hat status is '${indicator}' (fail-on-outage is enabled)"
  exit 1
fi
