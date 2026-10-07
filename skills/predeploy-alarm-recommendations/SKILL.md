---
name: predeploy-alarm-recommendations
version: "2.0.0"
last_updated: "2026-07-01"
description: >
  Produce PROACTIVE CloudWatch alarm coverage recommendations for an application
  about to be deployed, before any incident. Given the resources being deployed —
  as a manifest OR as Infrastructure as Code (Terraform plan/source, CloudFormation,
  or CDK template) — recommend the baseline alarms it should have (metric, threshold,
  comparison, evaluation period, rationale) and flag coverage gaps, enriching from
  prior incidents in the account.
  Activate when: a pre-deployment observability review is requested, a request carries
  review_type=predeploy_observability, a CI pre-deploy gate asks for alarm
  recommendations, a user points the agent at a Terraform/CloudFormation/CDK stack and
  asks about alarm coverage, or asks "what alarms should I have before deploying this?"
  This skill is ADVISORY, not diagnostic, and is NOT an IaC validator — it does not
  lint IaC syntax (use cfn-lint/checkov) and does not troubleshoot live failures.
compatibility: >
  Tool-agnostic — invoke from any IDE/CLI over MCP, from a CI pipeline, or from the
  DevOps Agent chat/console; nothing is bound to a specific CI tool. Requires AWS CLI
  or SDK access with cloudwatch (Describe/List), ec2:Describe*, lambda:List*/Get*,
  rds:Describe*, elasticloadbalancing:Describe*, elasticache:Describe*,
  es:Describe*/es:List* (OpenSearch), opensearch:Describe*, s3:GetBucket*/s3:ListAllMyBuckets,
  cloudhsmv2:Describe*, cloudtrail:LookupEvents, and sts permissions. Read-only — this
  skill never creates or modifies resources.
---

# Pre-Deployment Alarm Recommendations

## When to use

Any time the goal is to recommend CloudWatch alarm coverage BEFORE a deployment, rather than diagnose something that already broke. Typical triggers:

- A CI/CD pre-deploy gate (any tool — or none) sends a manifest or an IaC artifact and asks for recommended alarms.
- A user points the agent at a **Terraform plan, CloudFormation template, or CDK stack** and asks "what alarms should this have before I deploy?"
- A request carries the tag `review_type=predeploy_observability`.
- A user asks "review our alarm coverage for this stack."

If the request is about an active incident or a firing alarm, this is NOT the right skill — use the service-specific troubleshooting skill instead.

## What this skill is NOT

- **Not an IaC validator.** It does not lint or validate IaC syntax, security, or correctness — that is the job of `cfn-lint`, `checkov`, `terraform validate`, or the IDE. This skill answers one question: *is the observability (alarm) coverage adequate for what is about to be deployed?*
- **Not post-deployment root cause analysis.** The DevOps Agent's native IaC awareness (pipeline/repo association) does post-deploy RCA. This skill is the pre-deploy, advisory companion — different lane.
- **Not an action.** It recommends; it never creates or modifies alarms.

## Core principle

Recommend a **baseline** per resource type, then **enrich from history**. Do not invent thresholds blindly: start from the baseline tables in `references/`, adjust for the environment (prod is stricter than dev), read the resource's own config for size-dependent thresholds, and add any alarm that maps to a failure mode this account has actually experienced (found via prior investigations / CloudTrail).

## Recommendation workflow

### Step 1 — Identify the resources (manifest OR IaC)

Determine every resource being deployed and its type. The input arrives in one of two shapes:

**(a) A manifest** — a list of `{ type, name, details }`. Group by resource type.

**(b) Infrastructure as Code** — detect the format and parse accordingly:

| Input | How to parse | Reference |
|-------|--------------|-----------|
| Terraform plan (`terraform show -json`) or `.tf` source | resources in `resource_changes[]` where `.change.actions` contains `create` | **T1** |
| CloudFormation template (`.yaml`/`.json`) | the top-level `Resources` map (logicalId + `Type` + `Properties`) | **T2** |
| CDK app | `cdk synth` first, then parse `cdk.out/*.template.json` as CloudFormation | **T2** |

Map each IaC resource type to its baseline tier using the mapping tables in T1/T2. If no manifest or IaC is supplied, discover recently changed resources instead:

```
aws cloudtrail lookup-events --lookup-attributes AttributeKey=EventName,AttributeValue=CreateFunction --max-results 20
aws cloudtrail lookup-events --lookup-attributes AttributeKey=EventName,AttributeValue=RunInstances --max-results 20
```

### Step 2 — Check existing coverage (find the gaps)

For resources that already exist, list alarms that reference them so you only recommend what is MISSING:

```
aws cloudwatch describe-alarms --query 'MetricAlarms[*].{Name:AlarmName,Namespace:Namespace,Metric:MetricName,Dimensions:Dimensions}'
```

Match on the resource's dimension value (InstanceId, FunctionName, DBInstanceIdentifier, LoadBalancer, CacheClusterId, DomainName, BucketName). A resource with zero matching alarms is a full coverage gap.

**IaC caveat:** resources defined in a Terraform plan or CloudFormation template usually **do not exist yet**, so `describe-alarms` finds nothing for them — that is expected for a true pre-deploy review; treat each as a gap. The one exception: if a CloudFormation/CDK template declares `AWS::CloudWatch::Alarm` resources for a resource, that is existing coverage declared in IaC — do not flag it as a gap (see T2).

### Step 3 — Enrich from prior investigations

Look at what has actually broken in this account so recommendations reflect real risk:

```
aws cloudtrail lookup-events --lookup-attributes AttributeKey=EventName,AttributeValue=UpdateFunctionConfiguration --max-results 20
```

If prior investigations exist for this account, prefer alarms that would have caught those past incidents, and call them out explicitly ("recommended because a prior incident was caused by X").

### Step 4 — Emit recommendations

For each recommended alarm, state: metric, namespace, statistic, threshold, comparison operator, evaluation period, and a one-line rationale. Read the resource's config for size-dependent thresholds (storage, memory, timeout). Map every recommendation to the deployable tiers in the companion `recommended-alarms.yaml` so the customer can deploy them directly. Read `references/guardrails.md` before finalizing. Output is **inline recommendations** — this skill does not send email or create resources.

## Baseline recommendation reference

Detailed per-tier runbooks live in `references/`. Summary:

| Tier | Runbook | Baseline alarms |
|------|---------|-----------------|
| EC2 | A1 | CPUUtilization high, StatusCheckFailed |
| Lambda | B1 | Errors, Throttles (and Duration approaching timeout) |
| RDS | C1 | CPUUtilization high, FreeStorageSpace low, DatabaseConnections high |
| ALB | D1 | HTTPCode_ELB_5XX_Count, TargetResponseTime p95, UnHealthyHostCount |
| ElastiCache | E1 | EngineCPUUtilization high, DatabaseMemoryUsagePercentage high, Evictions, CurrConnections high |
| OpenSearch | E2 | ClusterStatus.red/yellow, JVMMemoryPressure, FreeStorageSpace low, ClusterIndexWritesBlocked |
| S3 | F1 | 5xxErrors (request-path-critical buckets only; often "no alarm needed") |
| CloudHSM | G1 | **Not covered** — limited CloudWatch metrics; recommend audit-log / cluster-state monitoring instead |
| Cross-cutting | Z1 | Environment-based severity, tagging, notification wiring |

## IaC parsing reference

| Format | Runbook |
|--------|---------|
| Terraform (plan JSON preferred, `.tf` fallback) | T1 |
| CloudFormation + CDK (synth → template) | T2 |

## Tool quick reference

| Tool / API | When to use |
|------------|-------------|
| `cloudwatch describe-alarms` | Find existing coverage; identify gaps |
| `cloudwatch list-metrics` | Confirm a metric is actually being published for the resource |
| `ec2 describe-instances` | Confirm EC2 resource + dimensions |
| `lambda get-function-configuration` | Confirm Lambda name, timeout (for Duration alarm) |
| `rds describe-db-instances` | Confirm RDS identifier, allocated storage (for FreeStorageSpace threshold) |
| `elasticloadbalancing describe-load-balancers` | Confirm ALB ARN suffix for the LoadBalancer dimension |
| `elasticache describe-cache-clusters` | Confirm cache cluster id, engine (Redis vs Memcached), node type |
| `opensearch describe-domain` | Confirm OpenSearch domain name, EBS volume size (for FreeStorageSpace) |
| `s3api get-bucket-metrics-configuration` | Confirm S3 request metrics are enabled (required for 4xx/5xx/latency alarms) |
| `cloudhsmv2 describe-clusters` | Confirm CloudHSM cluster state (monitored via logs/state, not threshold alarms) |
| `cloudtrail lookup-events` | Enrich from recent changes / past incidents |

## Anti-hallucination rules

1. Recommend alarms only for resources that actually appear in the manifest/IaC or in the account. Never invent resources.
2. Only claim a coverage gap after checking `describe-alarms` — OR, for IaC, after confirming no `AWS::CloudWatch::Alarm` for that resource is declared in the template. Do not assume.
3. Thresholds are starting points; state that they should be tuned to the workload. Never present a default threshold as guaranteed-correct.
4. FreeStorageSpace, memory, connection-count, and Duration thresholds depend on the resource's size/config — read the config (or IaC `Properties`/`change.after`) before giving a hard number.
5. This skill is advisory. Never state or imply that alarms were created. Creation is a separate, explicit deploy step.
6. Percentile alarms (p95/p99) use `ExtendedStatistic`, not `Statistic`.
7. Do NOT fabricate alarms for services without a credible CloudWatch baseline. CloudHSM (G1) has no baseline tier — recommend log/state monitoring, do not invent thresholds.
8. When enriching from history, cite the specific event or prior investigation. Do not claim "past incidents" without evidence.
9. Do NOT validate or lint the IaC. If the template is malformed, say that validation is out of scope (cfn-lint/checkov/terraform validate) and review only the resources you can read.

## Runbooks

| Category | IDs | Covers |
|----------|-----|--------|
| A — Compute (EC2) | A1 | EC2 baseline alarm recommendations |
| B — Serverless (Lambda) | B1 | Lambda baseline alarm recommendations |
| C — Data (RDS) | C1 | RDS baseline alarm recommendations |
| D — Edge (ALB) | D1 | ALB baseline alarm recommendations |
| E — Cache & Search | E1–E2 | ElastiCache, OpenSearch baseline alarm recommendations |
| F — Storage (S3) | F1 | S3 baseline (request-path-critical only; often none) |
| G — Not Covered | G1 | CloudHSM — deliberately excluded; log/state monitoring |
| T — IaC Parsing | T1–T2 | Terraform, CloudFormation/CDK resource extraction |
| Z — Catch-All | Z1 | Cross-cutting: severity, tagging, notifications, gap synthesis |
