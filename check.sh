#!/usr/bin/env bash
# Relay SEO check: start a check of the preview, wait for it, write the job
# summary, and fail according to fail-on. Needs only curl and jq.
set -uo pipefail

summary="${GITHUB_STEP_SUMMARY:-/dev/null}"
case "${FAIL_ON:-blocking}" in blocking | warning | never) ;; *) FAIL_ON=blocking ;; esac

# A Relay problem never fails the job, unless fail-on is warning.
give_up() {
  echo "Relay could not complete the check: $1"
  echo "Relay could not complete the check: $1" >>"$summary"
  [ "$FAIL_ON" = "warning" ] && exit 1
  exit 0
}

changed='[]'
if [ -n "${BASE_REF:-}" ]; then
  git fetch --quiet --depth=50 origin "$BASE_REF" 2>/dev/null || true
  changed=$(git diff --name-only "origin/$BASE_REF...HEAD" 2>/dev/null |
    head -n 300 | jq -R . | jq -s . 2>/dev/null) || changed='[]'
fi

# The release gate settings in the repository, sent as text when present.
gate='null'
if [ -f "${CONFIG_PATH:-relay-gate.json}" ]; then
  gate=$(jq -Rs . <"${CONFIG_PATH:-relay-gate.json}") || gate='null'
fi

body=$(jq -n \
  --arg previewUrl "$PREVIEW_URL" \
  --arg repository "$REPOSITORY" \
  --arg headSha "$HEAD_SHA" \
  --arg pr "${PR_NUMBER:-}" \
  --argjson changedFiles "$changed" \
  --argjson override "${OVERRIDE:-false}" \
  --argjson gateConfig "$gate" \
  '{previewUrl: $previewUrl, repository: $repository, headSha: $headSha,
    pullRequest: (if $pr == "" then null else ($pr | tonumber) end),
    changedFiles: $changedFiles, override: $override}
    + (if $gateConfig == null then {} else {gateConfig: $gateConfig} end)')

response=$(curl -sS -w '\n%{http_code}' -X POST "$RELAY_URL/api/ci/v1/checks" \
  -H "Authorization: Bearer $RELAY_TOKEN" -H "Content-Type: application/json" \
  --data "$body") || give_up "the request failed"
status=$(tail -n1 <<<"$response")
json=$(sed '$d' <<<"$response")
# An invalid relay-gate.json is a mistake in the pull request: it fails.
if [ "$(jq -r '.error // ""' <<<"$json" 2>/dev/null)" = "invalid_gate_config" ]; then
  message=$(jq -r '.message' <<<"$json")
  echo "$message"
  echo "$message" >>"$summary"
  exit 1
fi
if [ "$status" -ge 300 ]; then
  give_up "$(jq -r '.message // .error // "unknown error"' <<<"$json" 2>/dev/null || echo "HTTP $status")"
fi
run_id=$(jq -r '.id' <<<"$json")
echo "Relay check $run_id started for $PREVIEW_URL"

deadline=$(($(date +%s) + ${TIMEOUT_MINUTES:-10} * 60))
while :; do
  json=$(curl -sS "$RELAY_URL/api/ci/v1/checks/$run_id" \
    -H "Authorization: Bearer $RELAY_TOKEN") || json='{}'
  state=$(jq -r '.status // "unknown"' <<<"$json")
  case "$state" in succeeded | failed) break ;; esac
  [ "$(date +%s)" -ge "$deadline" ] && give_up "the check did not finish in ${TIMEOUT_MINUTES:-10} minutes"
  sleep 10
done
[ "$state" = "failed" ] && give_up "$(jq -r '.error // "the check failed"' <<<"$json")"

blocking=$(jq -r '.blocking' <<<"$json")
warnings=$(jq -r '.warnings' <<<"$json")
pages=$(jq -r '.urls' <<<"$json")
{
  echo "## Relay SEO check"
  echo
  echo "$pages pages checked: **$blocking blocking**, $warnings warnings."
  # Findings by rule pack, the file's ignore rules and the trend.
  summary_text=$(jq -r '.summary // ""' <<<"$json")
  [ -n "$summary_text" ] && echo && echo "$summary_text"
  if [ "$(jq '.findings | length' <<<"$json")" -gt 0 ]; then
    echo
    echo "<details><summary>Details</summary>"
    echo
    echo "| Severity | Pack | Page | Rule | Before | After | Clicks (28 d) | Impressions (28 d) |"
    echo "| --- | --- | --- | --- | --- | --- | --- | --- |"
    jq -r '.findings | sort_by(-(.impressions28d // 0)) | .[] |
      "| \(.severity) | \(.pack // "seo") | \(.path) | \(.rule) | \(.before // "" | gsub("\\|"; "/")) | \(.after // "" | gsub("\\|"; "/")) | \(.clicks28d // "") | \(.impressions28d // "") |"' <<<"$json"
    echo
    echo "</details>"
  fi
  [ "${OVERRIDE:-false}" = "true" ] && echo && echo "The relay-seo-override label is set: blocking findings do not fail this job."
} >>"$summary"
jq -r '.findings[] | "\(.severity): \(.path) \(.rule): \(.message)"' <<<"$json"

if [ "${OVERRIDE:-false}" != "true" ] && [ "$FAIL_ON" != "never" ] && [ "$blocking" -gt 0 ]; then
  echo "Relay found $blocking blocking SEO regressions."
  exit 1
fi
if [ "$FAIL_ON" = "warning" ] && [ "$warnings" -gt 0 ]; then
  echo "Relay found $warnings SEO warnings."
  exit 1
fi
echo "Relay SEO check passed."
