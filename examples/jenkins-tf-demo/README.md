# Jenkins + Terraform demo — deploy real resources, auto-review alarm coverage

End-to-end demo (validated working): a Jenkins pipeline deploys **real** AWS resources
with Terraform, then notifies the Observability Agent (custom DevOps Agent), which
reviews CloudWatch alarm coverage and returns recommendations in its run history.

```
Jenkins job
  ├─ terraform init
  ├─ terraform plan -out  → terraform show -json → plan.json   (captures CREATE actions)
  ├─ terraform apply (the saved plan)             → real t3.micro EC2 + S3 (NO alarms)
  └─ Notify stage: slim INCIDENT payload → HMAC-signed POST → Agent Space webhook (200)
                                                        │
                                   (two independent consumers of the webhook event:)
                                   ├─ always: a generic Investigation (incident default)
                                   └─ event trigger matches data.resources[?action=='create']
                                                        ▼
                                        pre-deploy-observability-reviewer custom agent
                                          → CloudWatch coverage recommendations
```

Tool-agnostic by design: Jenkins only POSTs a signed event; the review logic lives in
the agent + skill. The same POST step runs unchanged in any CI (GitHub Actions, GitLab,
CodeBuild).

---

## ⚠️ Prerequisites you MUST get right (these are the things that bite)

### 1. The event trigger (and its filter path)

The pipeline POSTs to your Agent Space webhook. The webhook does TWO things with an
`eventType: "incident"` event, independently:

- It **always** spins up a generic **Investigation** (that's the default for incident
  events — expected background noise, ignore it).
- **Separately**, your custom agent's **event trigger** evaluates its filter against the
  same payload and runs the custom agent only if the filter matches.

Create the trigger: DevOps Agent web app → **Agents** → `pre-deploy-observability-reviewer`
→ **Triggers** → **Create trigger** → **Event** → **Event source:** your webhook
integration → **Filter expression:**

```
data.resources[?action=='create']
```

> **Critical:** the filter path is `data.resources`, NOT `resources`. The payload nests
> the resource list under `data` (incident schema — see below). A top-level
> `resources[?action=='create']` evaluates against the root, finds nothing, and the
> trigger never fires even on a perfect payload. This cost us a full debugging cycle.

### 2. The payload is the fixed INCIDENT schema (not a custom shape)

The generic webhook rejects a custom top-level shape (e.g. `eventType: "deployment"`).
It requires the incident schema, with your resource detail nested in the free-form
`data` object:

```json
{
  "eventType": "incident",
  "incidentId": "tf-<stack>-<ts>",
  "action": "created",
  "priority": "MEDIUM",
  "title": "...",
  "description": "... review_type=predeploy_observability ...",
  "timestamp": "2026-10-14T22:06:19.000Z",
  "service": "Terraform",
  "data": { "review_type": "predeploy_observability", "resources": [ ... ] }
}
```

### 3. HMAC signing must be byte-exact

Signature = `base64( HMAC-SHA256( secret, "<timestamp>:<body>" ) )`, sent as headers
`x-amzn-event-timestamp` and `x-amzn-event-signature`. Two gotchas we hit, both now
handled in the Jenkinsfile:

- **Timestamp needs milliseconds** — `...T22:06:19.000Z`, matching JavaScript
  `toISOString()`. A second-precision timestamp signs a different string than the server
  reconstructs → 403.
- **Signed bytes must equal sent bytes** — `jq` writes the payload file with a trailing
  newline. `$(cat file)` in a shell substitution strips it, but `--data-binary @file`
  sends it. The Jenkinsfile builds the exact signing input in a file so signed == sent.

A mismatch on any of these surfaces as a generic **403 "Invalid request"**.

### 4. The whitelisted config fields must include the resource's size field

The slim filter keeps only specific `config` keys to stay under the 10K limit. It MUST
include the field that carries each resource's size/capacity, or the agent only sees
tags and falls back to baseline-default thresholds. The filter includes
`instance_type` (EC2), `instance_class`/`allocated_storage` (RDS), `memory_size`/`timeout`
(Lambda), `node_type` (ElastiCache), `volume_size`/`ebs_volume_size`/`instance_count`
(OpenSearch). If you add a resource type, add its size field here too.

---

## Customizing what the agent considers

The agent can only reason about what the payload contains. What reaches it is governed
by **two knobs**, plus a free-form escape hatch:

### Knob 1 — the slim-filter whitelist (which plan fields reach the agent)

The jq step in the Notify stage keeps only an allow-list of `config` keys (to stay under
the 10K limit). A field in the Terraform plan that is NOT on the list is dropped before
the agent sees it — which is exactly why EC2 recommendations once fell back to defaults:
`instance_type` was missing from the list. To have the agent factor in another field
(e.g. RDS `storage_type`, `multi_az`, or EBS `iops`), add that field name to the jq
whitelist in the Notify stage (and in `../slim-plan.jq` if you use the portable hook).

Rule of thumb: if it is size/capacity-related and the skill's runbook already uses it,
whitelisting it is all you need. Keep the list lean — the whitelist exists because a
full plan exceeds the 10K input cap.

### Knob 2 — the skill runbooks (how a field maps to an alarm)

A field only changes a recommendation if the skill knows what to do with it. The RDS
runbook (C1) uses `allocated_storage` to derive the FreeStorageSpace threshold; the EC2
runbook (A1) treats a burstable `instance_type` as a reason to add CPUCreditBalance. If
you pass a field the runbooks do not reference (say, a company-specific tag), the agent
sees it but has no rule tying it to an alarm. For such fields, extend the relevant
runbook under `../../skills/predeploy-alarm-recommendations/references/`.

### Escape hatch — free-form `data`

The payload's `data` object is free-form. To pass a one-off instruction without editing
jq (e.g. "prod databases must alarm on ReplicaLag"), add it as text under `data`. The
agent reads it as context. Good for ad-hoc policy; use the runbooks for anything you
want applied consistently.

### Resource ARNs (merged from post-apply state)

The pipeline attaches each resource's **real ARN** to its own `config.arn`, so the agent
can emit concrete alarm dimensions (exact InstanceId / LoadBalancer suffix / etc.) rather
than post-deploy placeholders. ARNs are **computed-after-apply** — they do not exist in
the plan — so the Apply stage captures post-apply state (`terraform show -json >
state.json`) and the Notify stage merges `address -> arn` onto each resource by Terraform
address. This per-resource attachment (not a flat outputs blob) means the agent never has
to guess which ARN belongs to which resource, which stays correct even with several
resources of the same type. Note this makes the flow inherently **post-apply** (resources
exist when the agent reviews them), which is already how this pipeline runs.

---

## Prerequisites (environment)

- Docker (runs Jenkins locally).
- AWS credentials that can create EC2 + S3 (and destroy them after). **`terraform apply`
  creates REAL, billable resources** — tiny (t3.micro + empty S3), but tear them down.
- Your Agent Space webhook URL and shared secret.

---

## 1. Build and start Jenkins (with AWS creds as static env keys)

The base `jenkins/jenkins` image has none of terraform/aws/jq/openssl — the demo
`Dockerfile` installs them. For credentials, this demo passes **static temporary keys
as env vars**, NOT a mounted `~/.aws` profile.

> **Why not mount `~/.aws`?** Isengard/SSO profiles use
> `credential_process = isengardcli`, which does not exist inside the container, so a
> mounted profile fails with "No such file: isengardcli". Static keys sidestep that.

On your host, export fresh creds, then build/start:

```bash
# get temp creds for the account (e.g. isengardcli credentials <profile> --format env)
export AWS_ACCESS_KEY_ID=ASIA...
export AWS_SECRET_ACCESS_KEY=...
export AWS_SESSION_TOKEN=...          # required for temporary creds
export AWS_REGION=us-east-1

cd devops-auto/custom-agent/examples/jenkins-tf-demo
docker compose up -d --build
```

Jenkins: http://localhost:8080 (admin / admin).

> **Creds expire.** Containers capture env at creation time. When the temp keys expire,
> re-export them on the host and recreate the container so it picks up the new values:
> `docker compose up -d --force-recreate`. (The `jenkins_home` volume persists, so your
> job config and credentials survive.) Verify with:
> `docker exec obs-agent-jenkins-demo aws sts get-caller-identity`.

## 2. Add Jenkins credentials

**Manage Jenkins → Credentials → (global) → Add Credentials** — two "Secret text" entries:

| ID | Secret |
|----|--------|
| `webhook-url` | your Agent Space webhook URL (`https://event-ai.<region>.api.aws/webhook/generic/<id>`) |
| `webhook-secret` | the webhook shared secret |

Paste values with no quotes and no trailing newline. If you rotate the webhook secret in
the console, update `webhook-secret` here — Jenkins reads it fresh each build, **no
container recreate needed** (unlike AWS creds, which are container env).

## 3. Create the pipeline job (Pipeline from SCM)

- **New Item → Pipeline**, name it e.g. `tf-alarm-review-demo`.
- **Pipeline → Definition: Pipeline script from SCM** → Git.
  - **Repository URL:** your repo (e.g. `https://github.com/<you>/observability-devops-agent`)
  - **Credentials:** none if the repo is public; otherwise a GitHub PAT credential.
  - **Branches to build:** `*/main`
  - **Script Path:** `examples/jenkins-tf-demo/Jenkinsfile`
    (repo-relative — this repo IS the custom-agent folder, so there is no
    `devops-auto/custom-agent/` prefix.)

> SCM checkout lands the whole repo in the workspace, so `main.tf` is at
> `examples/jenkins-tf-demo/main.tf`. The Jenkinsfile runs all terraform/jq steps inside
> that subdir via `dir("${TF_DIR}")`. (If you instead paste the pipeline inline with no
> SCM checkout, use `Jenkinsfile.inline`, which `writeFile`s main.tf into the workspace.)

## 4. Run it

**Build with Parameters:**
- `AWS_REGION` — e.g. `us-east-1`
- `STACK_NAME` — payload label, e.g. `obs-agent-demo`
- `DESTROY_AFTER` — **leave unchecked** so you can verify the review before teardown.

Console check:
- `Slim payload size: <~1KB> chars` with a **non-empty** `data.resources`
- `Webhook responded HTTP 200`

Then confirm the custom agent ran (see next section).

---

## ⚠️ Re-running requires a destroy first (Terraform is idempotent)

The filter matches `action == "create"`. Terraform only reports `create` for resources
that **don't exist yet**. After a successful apply, the resources exist, so the next
run's plan is a **no-op** → `data.resources: []` → the trigger's filter doesn't match →
the custom agent doesn't fire (and the webhook even rejects an empty event).

So for each demo run: **destroy first, then run.** From your host:

```bash
docker exec -e AWS_REGION=us-east-1 obs-agent-jenkins-demo \
  sh -c 'cd /var/jenkins_home/workspace/<JOB_NAME>/examples/jenkins-tf-demo \
         && terraform destroy -auto-approve -no-color -var region=us-east-1'
```

(Replace `<JOB_NAME>` with your pipeline job's name. "0 destroyed" = already clean;
"2 destroyed" = it removed the EC2 + S3.)

> If you want frictionless repeat demos without destroying, change the trigger filter
> and the Jenkinsfile to review ALL resources rather than only creates — but create-only
> is the more honest "new resources trigger a review" story.

---

## Confirming the custom agent actually ran

A webhook 200 means *accepted*, not *agent ran*. To verify the custom agent fired:

- **Console:** open `pre-deploy-observability-reviewer` → its run history. A run titled
  `Event trigger: eventChannel` with your resources in the payload = success. (A generic
  Investigation also appears — that's the incident-webhook default, not the custom agent.)
- **Programmatically:** list CUSTOM tasks for the agent space and look for a new task
  with `assetId` = your agent's asset id and `trigger_id` = your event trigger's goal id.

---

## Teardown (do not skip)

Resources are real and billable. Destroy with the command above (or run the job with
`DESTROY_AFTER=true` for a one-shot). Stop Jenkins with `docker compose down` (`-v` also
deletes the Jenkins home volume).

---

## Fallback: prove the agent without the webhook/trigger

To test the agent's behavior independent of the webhook routing, invoke it directly by
asset id (`ki-46453028-8cdf-429c-aa4f-ffa572945cfc`) — e.g. the Kiro MCP
`create_custom_agent_task`, or the DevOps Agent API. This bypasses the webhook and the
event trigger entirely; useful to confirm the skill/behavior while debugging routing.

---

## Notes

- **Advisory, not a gate:** a 200 means the agent was notified; the pipeline does not
  block on the review outcome. Make it blocking only with a deliberate follow-up poll.
- **Timing:** the pipeline plans first (to capture creates), then applies that plan, so
  the payload reflects what is being created. The review runs just after apply.
- **Verify in your account:** webhook accepts the signature, the trigger filter matches
  your payload shape (`data.resources[...]`), and egress to the webhook is allowed by
  account guardrails.
