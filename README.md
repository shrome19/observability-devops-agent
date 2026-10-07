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

## Triggering it automatically (optional)

Because it is a custom agent, you can attach a **scheduled trigger** in the Agent Space
to run it on a cadence, or invoke it from any CI step (a GitHub Action, GitLab job, or
CodeBuild phase) that calls the DevOps Agent MCP/API with the IaC as input. None of
those are required — a human asking in the IDE is a complete workflow on its own.
