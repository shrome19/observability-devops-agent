#!/usr/bin/env bash
#
# review-alarms.sh — post-apply pre-deploy observability hook for a Terraform pipeline.
#
# Runs right after `terraform apply` (or `terraform plan`) in CI. It:
#   1. captures the plan as JSON (terraform show -json)
#   2. slims it to the sub-10,000-char payload the agent accepts (via slim-plan.jq)
#   3. HMAC-signs the exact payload bytes and POSTs them to the Agent Space webhook
#
# The signing scheme matches the DevOps Agent webhook contract (and this repo's
# alarm-ingestion Lambda): HMAC-SHA256 over "<timestamp>:<body>", base64, sent as
#   x-amzn-event-timestamp: <ISO8601 timestamp>
#   x-amzn-event-signature: <base64 HMAC>
#
# Requirements: terraform, jq, openssl, curl. Run from the Terraform working dir.
#
# Environment variables (set these as CI secrets, NEVER hardcode):
#   AGENT_WEBHOOK_URL     - the Agent Space webhook URL (event-trigger integration)
#   AGENT_WEBHOOK_SECRET  - the shared secret for HMAC signing
# Optional:
#   TF_PLAN_FILE          - existing plan file to use (default: produce a fresh one)
#   SLIM_JQ               - path to slim-plan.jq (default: alongside this script)
#   STACK_NAME            - label for the payload (default: basename of the dir)
#   DRY_RUN               - if "true", print the signed request instead of POSTing

set -euo pipefail

: "${AGENT_WEBHOOK_URL:?Set AGENT_WEBHOOK_URL (the Agent Space webhook URL)}"
: "${AGENT_WEBHOOK_SECRET:?Set AGENT_WEBHOOK_SECRET (the webhook shared secret)}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SLIM_JQ="${SLIM_JQ:-$SCRIPT_DIR/../slim-plan.jq}"
STACK_NAME="${STACK_NAME:-$(basename "$PWD")}"

if [[ ! -f "$SLIM_JQ" ]]; then
  echo "ERROR: slim-plan.jq not found at $SLIM_JQ (set SLIM_JQ to its path)" >&2
  exit 1
fi

# --- 1. capture the plan as JSON -------------------------------------------------
PLAN_JSON="$(mktemp)"
trap 'rm -f "$PLAN_JSON" "$PAYLOAD" 2>/dev/null || true' EXIT

if [[ -n "${TF_PLAN_FILE:-}" ]]; then
  terraform show -json "$TF_PLAN_FILE" > "$PLAN_JSON"
else
  # produce a plan without applying; swap for your pipeline's existing plan file
  terraform plan -out=tfplan.bin -input=false >/dev/null
  terraform show -json tfplan.bin > "$PLAN_JSON"
fi

# --- 2. slim it to the sub-10K payload ------------------------------------------
PAYLOAD="$(mktemp)"
jq --arg stack "$STACK_NAME" -f "$SLIM_JQ" "$PLAN_JSON" \
  | jq --arg stack "$STACK_NAME" '.stack = $stack' > "$PAYLOAD"

PAYLOAD_SIZE="$(wc -c < "$PAYLOAD" | tr -d ' ')"
echo "Slim payload: ${PAYLOAD_SIZE} chars (agent input limit is 10000)"
if [[ "$PAYLOAD_SIZE" -ge 10000 ]]; then
  echo "ERROR: slim payload is >=10000 chars. Narrow the jq whitelist or split the stack." >&2
  exit 1
fi

# nothing being created? skip the call (matches the trigger's action=='create' gate)
CREATE_COUNT="$(jq '[.resources[]? | select(.action=="create")] | length' "$PAYLOAD")"
if [[ "$CREATE_COUNT" -eq 0 ]]; then
  echo "No resources with action=create in this plan — skipping agent review."
  exit 0
fi

# --- 3. HMAC-sign the EXACT bytes and POST --------------------------------------
# The timestamp in the signature MUST equal the header; the signed body MUST equal
# the posted body. Sign the file bytes directly to guarantee that.
TS="$(date -u +%Y-%m-%dT%H:%M:%S.000Z)"
BODY="$(cat "$PAYLOAD")"
SIG="$(printf '%s' "${TS}:${BODY}" \
  | openssl dgst -sha256 -hmac "$AGENT_WEBHOOK_SECRET" -binary \
  | openssl base64 -A)"

if [[ "${DRY_RUN:-false}" == "true" ]]; then
  echo "--- DRY RUN (not posting) ---"
  echo "POST $AGENT_WEBHOOK_URL"
  echo "x-amzn-event-timestamp: $TS"
  echo "x-amzn-event-signature: $SIG"
  echo "body:"; echo "$BODY"
  exit 0
fi

HTTP_CODE="$(curl -sS -o /tmp/agent-resp.txt -w '%{http_code}' \
  -X POST "$AGENT_WEBHOOK_URL" \
  -H 'Content-Type: application/json' \
  -H "x-amzn-event-timestamp: $TS" \
  -H "x-amzn-event-signature: $SIG" \
  --data-binary "@$PAYLOAD")"

echo "Webhook responded HTTP $HTTP_CODE"
cat /tmp/agent-resp.txt 2>/dev/null || true
echo

# 2xx = accepted. The agent runs asynchronously; results land in its run history
# (and wherever you've wired notifications), not in this HTTP response.
if [[ "$HTTP_CODE" =~ ^2 ]]; then
  echo "Review triggered. Check the agent's run history for the coverage report."
else
  echo "ERROR: webhook rejected the request (HTTP $HTTP_CODE)." >&2
  echo "Common causes: signature mismatch (timestamp/body not byte-identical)," >&2
  echo "wrong secret, or payload over 10000 chars." >&2
  exit 1
fi
