# Jenkins + Terraform demo — deploy real resources, auto-review alarm coverage

End-to-end demo: a Jenkins pipeline deploys **real** AWS resources with Terraform, then
notifies the Observability Agent (custom DevOps Agent), which reviews CloudWatch alarm
coverage and returns recommendations in its run history.

```
Jenkins job
  ├─ terraform init
  ├─ terraform apply   → real t3.micro EC2 + S3 bucket (NO alarms)
  ├─ terraform show -json → plan.json
  └─ Notify stage: slim payload → HMAC-signed POST → Agent Space webhook
                                                        │
                                                        ▼  event trigger fires
                                        pre-deploy-observability-reviewer
                                          → CloudWatch coverage recommendations
```

This shows the tool-agnostic story: Jenkins only POSTs a signed event; the review logic
lives in the agent + skill. The same POST step runs unchanged in any CI.

---

## ⚠️ One-time prerequisite you MUST do first: the event trigger

The pipeline POSTs to your Agent Space webhook. For that POST to actually run **your**
custom agent, an **event trigger** must connect the webhook to the agent. You have the
webhook integration already; create the trigger:

1. DevOps Agent web app → **Agents** → open `pre-deploy-observability-reviewer`.
2. **Triggers** tab → **Create trigger** → **Event**.
3. **Event source:** your connected webhook integration.
4. **Filter expression:** `resources[?action=='create']`
   (fires only when something is being created; passes just those resources as context).
5. Save.

Without this trigger, the webhook accepts the POST (HTTP 2xx) but nothing runs. If you
cannot create it yet, you can still prove the agent works via direct invocation (see
"Testing without the trigger" below).

---

## Prerequisites

- Docker (to run Jenkins locally).
- AWS credentials with permission to create EC2 + S3 (and to destroy them after).
  - **Heads-up:** `terraform apply` here creates REAL, billable resources. They are
    tiny (t3.micro + empty S3 bucket) but you MUST tear them down (see Teardown).
- The webhook URL and shared secret from your Agent Space webhook integration.

---

## 1. Build and start Jenkins

```bash
cd devops-auto/custom-agent/examples/jenkins-tf-demo
# make your AWS creds available to the container (mounts ~/.aws read-only by default)
export AWS_PROFILE=your-profile          # or set static keys in docker-compose.yml
docker compose up -d --build
```

Jenkins comes up at http://localhost:8080 (admin / admin). The image includes
terraform, aws cli, jq, and openssl.

> If your AWS access is via short-lived creds (e.g. Isengard/Midway), the mounted
> `~/.aws` must contain currently-valid credentials when the job runs. Refresh them if
> the apply fails with an auth error.

## 2. Add Jenkins credentials

**Manage Jenkins → Credentials → (global) → Add Credentials**, two "Secret text" entries:

| ID | Secret |
|----|--------|
| `webhook-url` | your Agent Space webhook URL |
| `webhook-secret` | the webhook shared secret |

(The Jenkinsfile references these IDs via `credentials('webhook-url')` / `('webhook-secret')`.)

## 3. Create the pipeline job

- **New Item → Pipeline**, name it `tf-alarm-review-demo`.
- **Pipeline → Definition: Pipeline script from SCM** (point at this repo), or paste the
  `Jenkinsfile` contents into an inline **Pipeline script**.
- Save.

## 4. Run it

**Build with Parameters:**
- `AWS_REGION` — e.g. `us-east-1`
- `STACK_NAME` — label for the payload, e.g. `obs-agent-demo`
- `DESTROY_AFTER` — check this to auto-`terraform destroy` at the end (recommended for a
  one-shot demo), or leave unchecked and destroy manually.

Watch the console: you'll see the apply create the EC2 + S3, the slim payload size
(well under 10K), and `Webhook responded HTTP 2xx`. Then open the custom agent's **run
history** — a new coverage review for `obs-agent-demo` appears within a minute.

---

## Teardown (do not skip)

The resources are real and billable. Either:
- Run the job with `DESTROY_AFTER=true`, **or**
- From the Jenkins workspace (or locally): `terraform destroy -auto-approve -var "region=us-east-1"`

To stop Jenkins: `docker compose down` (add `-v` to also delete the Jenkins home volume).

---

## Testing without the trigger (fallback)

If you have not created the event trigger yet and want to prove the agent produces a
review, invoke the custom agent directly instead of via the webhook — this is what the
Kiro MCP `create_custom_agent_task` call does (asset `ki-46453028-8cdf-429c-aa4f-ffa572945cfc`).
It bypasses the webhook/trigger entirely. The webhook path is the real automatic flow;
direct invocation is just a connectivity/behavior check.

---

## Notes

- **Signing:** HMAC-SHA256 over `<timestamp>:<body>`, base64, headers
  `x-amzn-event-timestamp` / `x-amzn-event-signature` — the same scheme as this repo's
  `alarm-ingestion` Lambda. The step signs and sends the exact same bytes (`--data-binary
  @slim_payload.json`) so the signature matches.
- **Timing:** this notifies the agent AFTER apply, so the resources exist — the agent can
  even check their live alarm state. To review BEFORE apply instead, move the Notify
  stage ahead of apply and build the payload from a `terraform plan` (not apply) output.
- **Advisory, not a gate:** a 2xx means the agent was notified; the pipeline does not
  block on the review. Make it blocking only with a deliberate follow-up poll step.
- **Verify in your account:** that the webhook accepts the signature, that the event
  trigger routes to this agent, and that egress to the webhook is allowed by your
  account guardrails.
