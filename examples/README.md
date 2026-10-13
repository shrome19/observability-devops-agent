# Example IaC inputs for the pre-deploy observability review

Two sample inputs you can hand the Observability Agent to see it in action. Both are
intentionally under-alarmed so the coverage gaps are obvious in a demo.

| Example | Format | What it demonstrates |
|---------|--------|----------------------|
| `sample-terraform/main.tf` | Terraform | Full-gap review — EC2 + RDS + ElastiCache with **zero** alarms. Every resource is a coverage gap. Exercises the T1 Terraform-parsing runbook. |
| `sample-cloudformation/sample-stack.yaml` | CloudFormation | **Mixed** coverage — a Lambda that already has an `Errors` alarm declared in the template (so the agent should NOT flag it) but is missing Throttles, plus an OpenSearch domain and S3 bucket with no alarms. Exercises the T2 runbook and the "existing coverage declared in IaC" path. |

## How to run

### Option A — from the DevOps Agent console (upload)
Open your `pre-deploy-observability-reviewer` custom agent in the DevOps Agent web app,
start a run/chat, and upload (or paste) the file. Ask:

> Review the CloudWatch alarm coverage for this IaC before deployment. Return inline
> recommendations and a coverage-gap summary.

### Option B — from an IDE over MCP (e.g. Kiro)
With the DevOps Agent connected over MCP, point the agent at the file in your workspace:

> Review the alarm coverage for `examples/sample-terraform/main.tf` before deployment.

### Option C — Terraform plan JSON (most reliable for Terraform)
Raw `.tf` is a supported fallback, but the JSON plan resolves variables/modules and is
the recommended input:

```bash
cd examples/sample-terraform
terraform init
terraform plan -out=tfplan
terraform show -json tfplan > plan.json
# then hand plan.json to the agent
```

## What to expect

- **Terraform sample:** all 3 resources reported as full coverage gaps, with EC2 /
  RDS / ElastiCache baseline alarms recommended. The RDS `FreeStorageSpace` threshold
  is derived from the declared `allocated_storage` (100 GiB), and the agent flags the
  single-node ElastiCache cluster as a resilience (non-alarm) concern.
- **CloudFormation sample:** the Lambda `Errors` alarm is recognized as existing
  coverage (NOT a gap); Lambda Throttles, the OpenSearch domain, and the S3 bucket are
  flagged as gaps. S3 is noted as request-path-dependent (often "no alarm needed").

These are advisory reviews — the agent recommends alarms, it does not create them, and
it does not validate IaC syntax (use `terraform validate` / `cfn-lint` / `checkov`).

> The sample files use fake AMI IDs, placeholder names, and no real credentials. They
> are safe to commit and share. Do not point the samples at real infrastructure.
