# Pre-Deployment Alarm Recommendations Skill

Agent skill for producing **proactive** CloudWatch alarm coverage recommendations
for an application that is about to be deployed — before any incident occurs.
Uses structured per-tier runbooks, anti-hallucination guardrails, and a
recommendation workflow that enriches a sensible baseline with lessons from prior
investigations in the account.

Unlike the troubleshooting skills in this catalog (which diagnose a live failure),
this skill is **advisory and recommendation-oriented**. It answers "what alarms
should this app have before we ship?" It never creates or modifies resources.

It is **tool-agnostic**: invoke it from any IDE/CLI over MCP, from any CI pipeline,
or straight from the DevOps Agent chat/console. Nothing is bound to a specific CI
tool. It reads the resources being deployed from either a plain manifest or from
**Infrastructure as Code** — a Terraform plan, a CloudFormation template, or a
CDK-synthesized template.

---

## What This Skill Covers

Given a description of the resources about to deploy (EC2, Lambda, RDS, ALB,
ElastiCache, OpenSearch, S3), recommend the baseline CloudWatch alarms the customer
should have, flag coverage gaps, and map each recommendation to a deployable
CloudFormation tier. CloudHSM is deliberately **not** covered (no credible generic
alarm baseline — see G1).

### What it is NOT

- **Not an IaC validator** — it does not lint or check IaC syntax/security. That is
  `cfn-lint`, `checkov`, `terraform validate`, or your IDE. This skill reviews
  observability coverage only.
- **Not post-deploy RCA** — the DevOps Agent's native pipeline/repo IaC awareness
  does post-deployment root cause analysis. This skill is the pre-deploy companion.
- **Not an action** — it recommends; deployment of the alarms is a separate step.

### Activate When

- A pre-deployment observability review is requested
- A request carries `review_type=predeploy_observability`
- A CI pre-deploy gate asks for alarm recommendations (any tool, or none)
- A user points the agent at a Terraform plan / CloudFormation / CDK stack
- A user asks "what alarms should I have before deploying this?" or "review our alarm coverage"

Do NOT activate for a live incident or a firing alarm — use the service-specific
troubleshooting skill instead.

---

## Skill Structure

```
predeploy-alarm-recommendations/
├── SKILL.md
├── README.md
└── references/
    ├── A1-ec2-alarms.md
    ├── B1-lambda-alarms.md
    ├── C1-rds-alarms.md
    ├── D1-alb-alarms.md
    ├── E1-elasticache-alarms.md
    ├── E2-opensearch-alarms.md
    ├── F1-s3-alarms.md
    ├── G1-cloudhsm-not-covered.md
    ├── T1-terraform-parsing.md
    ├── T2-cloudformation-parsing.md
    ├── Z1-cross-cutting.md
    ├── guardrails.md
    └── hallucination-patterns.yaml
```

---

## Runbook Library

| Category | IDs | Covers |
|----------|-----|--------|
| **A — Compute (EC2)** | A1 | EC2 baseline alarm recommendations |
| **B — Serverless (Lambda)** | B1 | Lambda baseline alarm recommendations |
| **C — Data (RDS)** | C1 | RDS baseline alarm recommendations |
| **D — Edge (ALB)** | D1 | ALB baseline alarm recommendations |
| **E — Cache & Search** | E1–E2 | ElastiCache, OpenSearch baseline alarm recommendations |
| **F — Storage (S3)** | F1 | S3 baseline (request-path-critical only; often none) |
| **G — Not Covered** | G1 | CloudHSM — deliberately excluded; log/state monitoring |
| **T — IaC Parsing** | T1–T2 | Terraform, CloudFormation/CDK resource extraction |
| **Z — Catch-All** | Z1 | Severity, tagging, notifications, gap synthesis |

---

## Two Ways to Use It

### 1. From an IDE / CLI over MCP (recommended, tool-agnostic)

Connect the DevOps Agent to your IDE (Kiro, Claude Code, Cursor) or CLI over MCP,
attach this skill to a custom agent, and ask it to review your IaC. No CI tool
required. See the companion `devops-auto/custom-agent/` folder for the custom-agent
system prompt and step-by-step setup.

Example prompt:
> Review the CloudWatch alarm coverage for the Terraform plan in this workspace.

### 2. From the Jenkins pre-deploy integration (legacy / one example CI)

This skill also powers the `devops-auto/jenkins-predeploy-alarms/` integration:

1. A Jenkins pre-deploy stage POSTs a deployment manifest to the pre-deploy gate
   Lambda, which forwards a review request tagged `review_type=predeploy_observability`.
2. The DevOps Agent activates THIS skill on that request and produces structured
   alarm recommendations following the per-tier runbooks.
3. The recommendations map to the tiers in
   `jenkins-predeploy-alarms/recommended-alarms.yaml`, which the customer can
   optionally deploy to create the recommended alarms.
4. Those alarms are tagged `auto_investigate=true`, so if they later fire, the
   alarm-ingestion pipeline forwards them back to the agent — closing the loop
   from proactive recommendation to automatic investigation.

Jenkins is just one example trigger. The skill itself does not depend on it.

---

## Install

1. Zip this folder: `zip -r predeploy-alarm-recommendations.zip predeploy-alarm-recommendations`
2. Open the AWS DevOps Agent web app
3. Go to **Settings** → **Add Skill** → **Upload Skill**
4. Select the `.zip` and upload
5. Attach the skill to a custom agent (see `devops-auto/custom-agent/README.md`)

The agent activates the skill automatically when it sees a matching pre-deploy
review request.

---

## Prerequisites

- AWS CLI v2 with read-only access: `cloudwatch:Describe*/List*`, `ec2:Describe*`,
  `lambda:List*/Get*`, `rds:Describe*`, `elasticloadbalancing:Describe*`,
  `elasticache:Describe*`, `es:Describe*`/`opensearch:Describe*`,
  `s3:GetBucket*`/`s3:ListAllMyBuckets`, `cloudhsmv2:Describe*`,
  `cloudtrail:LookupEvents`, `sts:GetCallerIdentity`.
- For IaC input: `terraform` (to produce `terraform show -json`) and/or the
  CloudFormation/CDK template files. `jq` is handy for parsing plan JSON.

---

## License

MIT-0
