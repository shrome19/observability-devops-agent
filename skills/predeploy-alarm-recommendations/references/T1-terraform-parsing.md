# T1 — Parsing Terraform to Extract Resources for Review

## Goal
Turn a Terraform project (or plan) into the list of `{ type, name, config }` resources the baseline tiers reason about — specifically the resources about to be **created**.

## Preferred input: the JSON plan
The most reliable input is the machine-readable plan, not raw `.tf` files (which can hide resources behind modules, variables, and `for_each`). The customer produces it with:

```
terraform plan -out=tfplan
terraform show -json tfplan > plan.json
```

Then reason over `plan.json`. The resources being created are in `resource_changes[]`:

```
# every resource this apply will CREATE
jq '.resource_changes[]
    | select(.change.actions | index("create"))
    | {address, type, name, values: .change.after}' plan.json
```

- `.resource_changes[].type` is the Terraform resource type (e.g. `aws_instance`).
- `.change.actions` contains `"create"` for new resources, `"update"`, `"delete"`, or `["no-op"]`. Review **create** (and optionally **update**) — skip `no-op` and `delete`.
- `.change.after` holds the resolved config (post-plan values), which is where you read instance type, allocated storage, timeout, etc. for size-dependent thresholds.

## Fallback input: raw `.tf` source
If only `.tf` files are available (no plan), scan for `resource "aws_*"` blocks. This is less reliable: values may be variables/locals not yet resolved, and `count`/`for_each` multiply resources. State clearly that recommendations are based on static source and should be re-confirmed against a real plan.

## Terraform type → baseline tier mapping

| Terraform resource type | Tier | Reference |
|-------------------------|------|-----------|
| `aws_instance` | EC2 | A1 |
| `aws_lambda_function` | Lambda | B1 |
| `aws_db_instance` | RDS | C1 |
| `aws_lb` / `aws_alb` (type = application) | ALB | D1 |
| `aws_elasticache_cluster` / `aws_elasticache_replication_group` | ElastiCache | E1 |
| `aws_opensearch_domain` / `aws_elasticsearch_domain` | OpenSearch | E2 |
| `aws_s3_bucket` | S3 | F1 (often "no alarm needed") |
| `aws_cloudhsm_v2_cluster` | — | G1 (not covered — log/state monitoring) |

Resource types not in this table have no defined baseline tier — note them as "reviewed, no baseline tier defined" rather than inventing alarms.

## Reading config for size-dependent thresholds
Pull these from `.change.after` so thresholds are grounded (Guardrail 4), not hardcoded:
- EC2: `instance_type` (burstable T-family → consider CPUCreditBalance).
- Lambda: `timeout` (Duration alarm = ~80% of it), `reserved_concurrent_executions`.
- RDS: `allocated_storage` (FreeStorageSpace threshold), `instance_class` (connection limit).
- ElastiCache: `node_type`, `engine` (Redis vs Memcached changes which metrics apply).
- OpenSearch: `ebs_options.volume_size`, `cluster_config.instance_count`.

## Important: these are intended resources, not deployed ones
A Terraform plan describes what *will* exist. The resources do not exist in the account yet, so `describe-alarms` coverage checks (Step 2 of the workflow) will find **nothing** for them — which is correct and expected for a true pre-deploy review. Treat every reviewed resource as a full coverage gap unless the customer says alarms are managed elsewhere. Do not claim an alarm "already exists" for a resource that has not been created.
