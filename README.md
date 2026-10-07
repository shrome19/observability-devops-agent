# Pre-Deploy Observability Reviewer — Custom DevOps Agent

A **tool-agnostic** way to run the pre-deploy alarm-coverage review: a DevOps Agent
**custom agent** with the `predeploy-alarm-recommendations` skill attached. You point
it at your Infrastructure as Code (Terraform, CloudFormation, or CDK) and it returns
inline alarm recommendations — no Jenkins, no API Gateway, no CI tool required.

This is the "unbind it from Jenkins" path. The Jenkins integration in
`devops-auto/jenkins-predeploy-alarms/` still works and is one example trigger, but
the custom agent below is the portable, CI-independent version.

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
- The `predeploy-alarm-recommendations` skill uploaded to that Agent Space
  (see `devops-auto/aws-devops-agent-skills/predeploy-alarm-recommendations/README.md`).
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
   repository**, point it at `devops-auto/custom-agent/system-prompt.md`.
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

## Step 2 — Attach the skill

If you did not attach it during creation (e.g. the import path), open the agent's
detail page and add the **predeploy-alarm-recommendations** skill. This is what gives
the agent the per-service baselines and the T1/T2 IaC parsing runbooks.

---

## Step 3 — Connect from Kiro (over MCP)

Already done if your `~/.kiro/settings/mcp.json` `powers` block has the
`power-aws-devops-agent-aws-devops-agent` server with a resolved URL + bearer token,
and `get_agent_space` returns your space (`shrome-demo`). If not, see
`devops-auto/jenkins-predeploy-alarms/README.md` or the AWS docs for the token setup
(DevOps Agent web app → Settings → Access Tokens).

---

## Step 4 — Run a review

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

The agent returns inline recommendations plus a coverage-gap summary, and maps them to
the tiers in `jenkins-predeploy-alarms/recommended-alarms.yaml` so you can deploy the
alarms if you choose.

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
