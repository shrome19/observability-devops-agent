# Terraform pipeline hook — automatic pre-deploy alarm review

Reference code for the **Terraform automatic-trigger path**: a post-apply (or
post-plan) step your CI/CD runs to send a slim deployment payload to the Observability
Agent's webhook, so the alarm-coverage review fires on every deploy without anyone
asking.

This is the path for **Terraform** users. There is no AWS-native "Terraform deployed"
event, so the trigger must come from the pipeline. (CloudFormation/CDK users can
instead use an EventBridge `CloudFormation Stack Status Change` rule — no pipeline
change needed.)

## Files

| File | What it is |
|------|------------|
| `review-alarms.sh` | Portable hook: capture plan → slim it → HMAC-sign → POST to the webhook. Works in any CI (GitHub Actions, GitLab, Jenkins, CodeBuild). |
| `github-actions-step.yml` | Example GitHub Actions job that runs `review-alarms.sh`. |
| `../slim-plan.jq` | The transform that keeps the payload under the 10,000-char limit. |

## How it works

```
terraform apply (or plan) in CI
   │
   ▼  review-alarms.sh
   1. terraform show -json  →  full plan JSON
   2. jq -f slim-plan.jq    →  slim payload (~1 KB, under the 10K cap)
   3. HMAC-SHA256 sign       →  x-amzn-event-timestamp + x-amzn-event-signature
   4. curl POST              →  Agent Space webhook (event-trigger integration)
   │
   ▼
Observability Agent runs, filtered by  resources[?action=='create']
   →  inline alarm-coverage review in the agent's run history
```

## Setup

1. **Connect a webhook integration** in your Agent Space (so it appears as an event
   source). Note its URL and shared secret.
2. **Create the event trigger** on the `pre-deploy-observability-reviewer` agent:
   - Event source: that webhook integration
   - Filter expression: `resources[?action=='create']` (gates to real creates and
     projects just those resources into context — keeping input under the cap)
3. **Store secrets in CI** (never hardcode): `AGENT_WEBHOOK_URL`, `AGENT_WEBHOOK_SECRET`.
4. **Add the step** — see `github-actions-step.yml`, or call `review-alarms.sh`
   directly from any CI tool with the two env vars set.

## Try it locally first (dry run)

From a Terraform working directory, with the two env vars set:

```bash
DRY_RUN=true AGENT_WEBHOOK_URL=https://example/webhook \
AGENT_WEBHOOK_SECRET=test-secret \
bash review-alarms.sh
```

`DRY_RUN=true` prints the signed request (payload, timestamp, signature) instead of
POSTing, so you can confirm the slim payload and signature look right before wiring the
real webhook.

## Signing contract (must match exactly)

The webhook verifies an HMAC the same way this repo's `alarm-ingestion` Lambda signs it:

- `signature = base64( HMAC-SHA256( secret, "<timestamp>:<body>" ) )`
- `x-amzn-event-timestamp` header = the **same** timestamp used in the signature
- the signed body = the **exact bytes** POSTed

If any of those differ by a byte (a re-serialized body, a regenerated timestamp), the
webhook rejects it. `review-alarms.sh` signs the exact payload file it sends to avoid
that.

## Notes / caveats

- **Advisory, not a gate.** The step confirms the webhook accepted the payload (HTTP
  2xx); it does not block the pipeline on the review outcome. The agent reviews
  asynchronously and writes to its run history. Make it blocking only if you add a
  follow-up poll step — a deliberate choice, not the default.
- **Timing.** A post-`apply` hook reviews resources that just went live (reactive). To
  review *before* apply, run the hook on the `plan` output in a pre-apply stage
  instead — same script, earlier in the pipeline.
- **Verify before relying on it:** the exact webhook URL/secret, that your account's
  guardrails permit the outbound POST, and that the event trigger's filter matches your
  payload shape. These are environment-specific — confirm with a `DRY_RUN` then a real
  trivial-resource apply.
