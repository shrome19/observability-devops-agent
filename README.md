# Pre-Deploy Observability Reviewer — Custom DevOps Agent

# Observability Agent — Pre-Deploy Alarm Coverage Reviewer

A **tool-agnostic** way to run a pre-deploy alarm-coverage review: a DevOps Agent
**custom agent** with the `predeploy-alarm-recommendations` skill attached. You point
it at your Infrastructure as Code (Terraform, CloudFormation, or CDK) and it returns
inline alarm recommendations — no Jenkins, no API Gateway, no CI tool required.

The custom agent is the portable, CI-independent way to run the review. It can also be
driven from any CI system (a pipeline stage that calls the DevOps Agent), but no CI
tool is required — a human asking in the IDE is a complete workflow.

---

## What's in this repo

```
.
├── system-prompt.md        # the custom agent's system prompt (import this)
├── README.md               # this file
└── skills/
    └── predeploy-alarm-recommendations/   # the skill the agent depends on
        ├── SKILL.md
        ├── README.md
        └── references/     # per-service baselines + IaC parsing runbooks
```

The agent is two parts, attached separately in the DevOps Agent console:
1. **System prompt** — `system-prompt.md` (defines behavior).
2. **Skill** — `skills/predeploy-alarm-recommendations/` (the alarm baselines and the
   Terraform/CloudFormation/CDK parsing runbooks). Uploaded as a zip, then attached.

---

## What the skill knows (runbook codes)

The skill is organized as per-service runbooks under
`skills/predeploy-alarm-recommendations/references/`. Each code is one reference file
defining the baseline CloudWatch alarms for a service (you will see these codes in the
agent's output, e.g. "Lambda → B1"):

| Code | Service | Baseline alarms |
|------|---------|-----------------|
| **A1** | EC2 | CPUUtilization, StatusCheckFailed (+ CPUCreditBalance for burstable) |
| **B1** | Lambda | Errors, Throttles, Duration-near-timeout |
| **C1** | RDS | CPUUtilization, FreeStorageSpace, DatabaseConnections |
| **D1** | ALB | HTTPCode_ELB_5XX, TargetResponseTime p95, UnHealthyHostCount |
| **E1** | ElastiCache | EngineCPUUtilization, DatabaseMemoryUsagePercentage, Evictions |
| **E2** | OpenSearch | ClusterStatus.red/yellow, JVMMemoryPressure, FreeStorageSpace |
| **F1** | S3 | 5xxErrors (request-path buckets only; often "no alarm needed") |
| **G1** | CloudHSM | *(deliberately none — monitor via logs/state, not threshold alarms)* |
| **T1** | Terraform parsing | how to read a `terraform show -json` plan |
| **T2** | CloudFormation/CDK parsing | how to read a CFN template / deployed stack |
| **Z1** | Cross-cutting | severity-by-environment, tagging, notifications, gap synthesis |

The skill is **advisory** — it recommends alarms and maps them to a deployable
`recommended-alarms.yaml`; it never creates resources, and it is not an IaC linter
(that is `cfn-lint`/`checkov`/`terraform validate`).

## Three ways to trigger it (all validated end to end)

| Path | How the agent is triggered | CI tool? | Where |
|------|----------------------------|----------|-------|
| **Manual** | Paste IaC / ask in the IDE or console | None | — |
| **Terraform** | CI pipeline step signs + POSTs the plan to the webhook | Any CI (demoed on Jenkins) | `examples/jenkins-tf-demo/`, `examples/pipeline/` |
| **CloudFormation / CDK** | EventBridge `Stack Status Change` → Lambda → webhook | None (event-native) | `examples/auto-trigger-cloudformation/` |

All three POST the same **incident-schema** payload (resources under `data.resources`),
HMAC-signed, to the Agent Space webhook; a single **event trigger** on the agent
(filter `data.resources[?action=='create']`) runs the custom agent. The webhook also
spins up a generic Investigation for incident events — that is expected and separate
from the custom-agent run.

---

## How this fits with other DevOps Agent capabilities

| Capability | Timing | Question it answers | Setup needed |
|------------|--------|---------------------|--------------|
| **This custom agent** | Pre-deploy | "Is my alarm coverage adequate for what I'm about to ship?" | Just the skill + an Agent Space |
| Release Readiness Review (built-in) | Pre-merge | "Is this *code change* safe to merge?" | PR/branch connection |
| Native IaC awareness (built-in) | Post-deploy | "What change broke this resource?" | Pipeline/repo association, GitHub App perms |
| cfn-lint / checkov / IDE | Pre-deploy | "Is my IaC *syntactically / securely* valid?" | Those tools |

This agent is an **observability-readiness companion** to Release Readiness Review —
same pre-ship moment, complementary question, different input (IaC resource state vs.
code diff). It does **not** require the pipeline association or GitHub App permissions
that post-deploy root cause analysis needs, because nothing has deployed yet.

---

## Prerequisites

- An Agent Space with at least one connected integration (your AWS account).
- The `predeploy-alarm-recommendations` skill uploaded to that Agent Space. The skill
  ships **inside this repo** at `skills/predeploy-alarm-recommendations/`
  (see its own `README.md` there for details).
- For running it from your IDE: the DevOps Agent connected over MCP (see "Connect
  from Kiro" below). You already have this working if `get_agent_space` returns your
  space.

---

## Step 1 — Create the custom agent

You can create it three ways. All produce the same agent stored in your Agent Space.

### Option A — Import this file from GitHub (recommended, version-controlled)
The DevOps Agent can import a custom agent's system prompt directly from a Markdown
file in a connected GitHub repo. `system-prompt.md` in this folder is written for
exactly that.

1. Push this repo (or just `system-prompt.md`) to a GitHub repo your Agent Space's
   connected GitHub account can read.
2. In the DevOps Agent web app → **Agents** → **Create agent** → **Import from
   repository**, point it at `system-prompt.md` at the repo root.
3. The file contents become the agent's system prompt. Name it
   `pre-deploy-observability-reviewer` (lowercase, hyphens, ≤64 chars).

### Option B — Form
1. **Agents** → **Create agent** → **Form**.
2. **Name:** `pre-deploy-observability-reviewer`.
3. **System prompt:** paste the contents of `system-prompt.md`.
4. **Skills:** select `predeploy-alarm-recommendations`.
5. Create.

### Option C — Chat (guided)
In the DevOps Agent Chat, say:
> Create a custom agent called pre-deploy-observability-reviewer that reviews
> Infrastructure as Code for CloudWatch alarm coverage before deployment, using the
> predeploy-alarm-recommendations skill. It should return inline recommendations and
> must not validate IaC or create any resources.

Chat will confirm intent, attach the skill, and draft the prompt for your review.

---

## Step 2 — Upload and attach the skill

The skill ships in this repo at `skills/predeploy-alarm-recommendations/`. Package it
and upload it to your Agent Space, then attach it to the agent.

1. **Zip the skill** (exclude macOS/editor junk, or the console upload will reject it):
   ```bash
   cd skills
   zip -r -X predeploy-alarm-recommendations.zip predeploy-alarm-recommendations \
     -x '*.DS_Store' -x '__MACOSX*'
   ```
2. **Upload:** DevOps Agent web app → **Settings → Add Skill → Upload Skill** → select
   the zip. The console validates the `SKILL.md` frontmatter (e.g. `description` must be
   ≤1024 characters), so upload the version from this repo, which is within limits.
3. **Attach:** open the agent's detail page and add the
   **predeploy-alarm-recommendations** skill. This is what gives the agent the
   per-service baselines and the T1/T2 IaC parsing runbooks.

---

## Step 3 — Choose the agent's tools

When creating or editing the agent, the DevOps Agent console presents a tool picker
(its built-in capabilities). Select the minimum set this advisory agent needs — and
deliberately leave off anything that can write, deploy, or orchestrate, so the agent
stays true to its "recommends, never acts" contract.

### Select — core (the agent cannot work without these)

| Tool | Why |
|------|-----|
| `use_aws` | The critical one. Runs the read-only AWS describe/list calls the skill's workflow depends on: `cloudwatch describe-alarms`, `ec2 describe-instances`, `lambda get-function-configuration`, `rds describe-db-instances`, `elasticloadbalancing describe-load-balancers`, `elasticache describe-cache-clusters`, `opensearch describe-domain`, `s3api get-bucket-metrics-configuration`, `cloudhsmv2 describe-clusters`. |
| `get_skill_resource` | Lets the agent read the attached skill's files (SKILL.md and the A1/B1/C1/D1/E1/E2/F1/G1/T1/T2/Z1 references) so it actually loads the baselines and IaC parsing runbooks. |
| `get_skill_resource_manifest` | Lets the agent discover which skill files exist before reading them. Pair with `get_skill_resource`. |

### Select — recommended (match specific skill steps)

| Tool | Why |
|------|-----|
| `lookup_cloudtrail_events` | Powers the skill's Step 3 "enrich from history" (`cloudtrail lookup-events`) — recommend alarms that would have caught past incidents. |
| `get_account_cloudformation_stacks` | When the IaC is a CloudFormation stack already deployed, reads its resources directly — complements the T2 CloudFormation/CDK parsing runbook. |

### Optional (only if you want extra behavior)

| Tool | Why / when |
|------|-----------|
| `explore_cloud_resource_topology`, `get_cloud_resource_topology`, `get_resource_edges` | Live topology mapping. Not needed for IaC-input review; add only if you also want the agent to look at how existing resources connect. |
| `get_other_agentspace_journal_records`, `get_recommendation_investigation_*` | Read prior investigations. Marginal for a pre-deploy review. |

### Do NOT select (keeps it advisory, read-only, and honest)

- Write / mutation: `upload_skill`, `create_or_update_artifact`, `attach_memory_stores`.
- Wrong platform: `use_azure`, `use_kubectl` (this is an AWS/CloudWatch use case).
- Multi-agent / investigation orchestration: `delegate_investigation`, `engage_members`, `escalate_to_lead`, `evaluate_plan`.
- Unrelated data sources: `execute_dql_query`, `get_prometheus_metrics`, the `get_trace_*` tools, `trusted_advisor_*`, `read_ticket_comments`, `query_cloudwatch_logs`.

### Minimum viable set

`use_aws`, `get_skill_resource`, `get_skill_resource_manifest`, `lookup_cloudtrail_events`.
Add `get_account_cloudformation_stacks` if you will review already-deployed CloudFormation stacks.

### ⚠️ Read-only is enforced by IAM, not by the tool list

`use_aws` is a **general** AWS tool — it can call far more than describe/list. The only
thing that keeps this agent read-only is the **IAM role** attached to it. Selecting
`use_aws` grants the capability; a least-privilege role is what enforces "advisory,
never acts." Scope the agent's role to read-only actions and nothing more:

```
cloudwatch:DescribeAlarms, cloudwatch:ListMetrics,
ec2:DescribeInstances,
lambda:ListFunctions, lambda:GetFunctionConfiguration,
rds:DescribeDBInstances,
elasticloadbalancing:DescribeLoadBalancers,
elasticache:DescribeCacheClusters,
es:DescribeElasticsearchDomain*,  opensearch:DescribeDomain,
s3:GetBucket*, s3:ListAllMyBuckets,
cloudhsmv2:DescribeClusters,
cloudtrail:LookupEvents,
sts:GetCallerIdentity
```

Do NOT grant `cloudwatch:PutMetricAlarm`, any `Create*`/`Update*`/`Delete*`, or deploy
permissions. The agent recommends alarms; deploying them (e.g. via a CloudFormation
baseline template) is a separate, explicit human step.

---

## Step 4 — Connect from Kiro (over MCP)

Already done if your `~/.kiro/settings/mcp.json` `powers` block has the
`power-aws-devops-agent-aws-devops-agent` server with a resolved URL + bearer token,
and `get_agent_space` returns your Agent Space. If not, see the AWS docs for the token
setup (DevOps Agent web app → Settings → Access Tokens).

---

## Step 5 — Run a review

### Terraform
```
terraform plan -out=tfplan
terraform show -json tfplan > plan.json
```
Then, in Kiro (or the DevOps Agent chat), ask the custom agent:
> Using the pre-deploy-observability-reviewer agent, review the alarm coverage for
> the Terraform plan in plan.json.

> ⚠️ **Input is capped at 10,000 characters.** A full `terraform show -json` plan
> blows past that for even a few resources (`after_unknown`, `sensitive_values`, and
> the `configuration` block are the bulk of it). Pasting a raw full plan fails with a
> generic "Failed to run agent" error — it is an input-size rejection, not an agent
> problem. **Pre-filter the plan to a slim payload first** (see
> [Payload size limit](#payload-size-limit-10000-characters) below). The repo ships a
> `jq` filter that reduces a full plan to ~1 KB:
> ```
> terraform show -json tfplan | jq -f examples/slim-plan.jq > slim-payload.json
> ```
> Paste `slim-payload.json`, not `plan.json`.

### CloudFormation
> Review the alarm coverage for the CloudFormation template at infra/template.yaml.

### CDK
```
cdk synth > /dev/null   # writes cdk.out/<Stack>.template.json
```
> Review the alarm coverage for the synthesized CDK template in cdk.out/.

The agent returns inline recommendations plus a coverage-gap summary, with the metric,
threshold, comparison, and evaluation period for each recommended alarm so you can
deploy them (e.g. via a CloudFormation baseline template) if you choose.

---

## What you get back

- Resources reviewed, grouped by type.
- Resources that would deploy with zero alarm coverage (the real gaps).
- Recommended alarms per tier: metric, threshold, comparison, evaluation period, rationale.
- The exact `recommended-alarms.yaml` parameters to deploy the recommended tiers.
- Honest notes where a service has no baseline (e.g. CloudHSM) or needs config to
  alarm (e.g. S3 request metrics).

It will not create alarms, deploy anything, or lint your IaC — it reviews observability
coverage and hands the decision back to you.

---

## Payload size limit (10,000 characters)

Both the manual **run-input field** and the **webhook event-trigger payload** are
capped at **10,000 characters**. A full `terraform show -json` plan routinely exceeds
this — our real 3-resource sample plan was ~13.8 KB. The cap is enforced *before* the
agent starts, so an oversized input fails with a generic "Failed to run agent" message
that looks like a config error but is not.

**Do not** rely on the event trigger's JMESPath filter to shrink a full plan — if the
projection still produces >10K characters, the agent gets no usable context (or does
not run). **Pre-filter at the source instead.** The repo ships
[`examples/slim-plan.jq`](examples/slim-plan.jq), which keeps only created resources
and the size/capacity fields the skill needs (dropping `after_unknown`,
`sensitive_values`, and `configuration`):

```
terraform show -json tfplan | jq -f examples/slim-plan.jq > slim-payload.json
```

On the sample plan this reduces 13,858 → ~1,200 characters. The slim shape looks like
[`examples/sample-terraform-plan/slim-payload.json`](examples/sample-terraform-plan/slim-payload.json).

---

## Triggering it automatically (optional)

The agent's **Triggers** tab supports both schedule-based and event-based triggers.

### Scheduled trigger
Attach a cron/rate trigger to run the agent on a cadence (e.g. a nightly scan of a
known IaC repo). Good for drift/coverage audits.

### Event trigger (webhook)
Fire the agent on a deployment event. There is no built-in Terraform/CloudFormation
integration that emits a webhook, so the pattern is:

```
terraform apply / CFN stack-complete
   │  (EventBridge rule on deploy-complete, or a CI pipeline step)
   ▼
Lambda  ──POST slim payload──▶  Agent Space webhook (event-trigger integration)
   ▼
pre-deploy-observability-reviewer  →  loads skill  →  inline alarm-coverage review
```

Key points:
1. **Pre-filter in the pipeline/Lambda** — POST the slim payload (the `slim-plan.jq`
   shape), NOT the raw plan. The 10K cap applies to the webhook payload too.
2. **Gate + project with a JMESPath filter** on the event trigger so the agent only
   runs for relevant deploys and receives just the created resources:
   ```
   resources[?action=='create']
   ```
   - Non-empty (something is being created) → truthy → the agent runs with that list.
   - Empty (update-only or destroy-only deploy) → no match → the agent does not run.
3. To pass metadata alongside the filtered resources, wrap it in an object literal
   (a projection that would otherwise be empty must be wrapped to pass through):
   ```
   {stack: stack, region: region, resources: resources[?action=='create']}
   ```

None of this is required — a human asking in the IDE is a complete workflow. The event
trigger is for teams that want the review to fire automatically on every deploy.
