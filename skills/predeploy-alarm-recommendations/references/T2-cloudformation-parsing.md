# T2 — Parsing CloudFormation (and CDK) to Extract Resources for Review

## Goal
Turn a CloudFormation template — or a CDK-synthesized template — into the list of `{ logicalId, type, config }` resources the baseline tiers reason about.

## CloudFormation is the easy case
A CloudFormation template is already a declarative resource map, so there is no plan step. The resources are the top-level `Resources` object, keyed by logical ID:

```
# list every resource and its type (YAML or JSON template)
# JSON:
jq '.Resources | to_entries[] | {logicalId: .key, type: .value.Type, props: .value.Properties}' template.json
```

For YAML templates, read the `Resources:` block directly — each key is a logical ID, each `Type:` is the CloudFormation resource type, and `Properties:` holds the config.

- Every resource under `Resources` is being **created** (or updated) by this stack — unlike Terraform, there is no per-resource "create vs no-op" action to filter on at the template level. If a changeset is available, `aws cloudformation describe-change-set` narrows to what actually changes, but the template alone is a valid pre-deploy input.
- `Properties` may contain `Ref`, `Fn::GetAtt`, `Fn::Sub`, and `!Ref`/`!Sub` (YAML) intrinsics that are not resolved until deploy. Read literal values where present; for intrinsics, note the value is deploy-time and may need confirmation.

## CDK: synthesize first, then treat as CloudFormation
CDK apps are not read directly — they synthesize to CloudFormation. The customer runs:

```
cdk synth > /dev/null          # writes templates to cdk.out/
# templates land at cdk.out/<StackName>.template.json
jq '.Resources | to_entries[] | {logicalId: .key, type: .value.Type}' cdk.out/<StackName>.template.json
```

Once synthesized, parse `cdk.out/*.template.json` exactly like any CloudFormation template using the mapping below. CDK logical IDs are auto-generated (hashed suffixes) — use the `Type` and any `Tags`/`aws:cdk:path` metadata to identify resources, not the logical ID alone.

## CloudFormation type → baseline tier mapping

| CloudFormation resource type | Tier | Reference |
|------------------------------|------|-----------|
| `AWS::EC2::Instance` | EC2 | A1 |
| `AWS::Lambda::Function` | Lambda | B1 |
| `AWS::RDS::DBInstance` | RDS | C1 |
| `AWS::ElasticLoadBalancingV2::LoadBalancer` (Type: application) | ALB | D1 |
| `AWS::ElastiCache::CacheCluster` / `AWS::ElastiCache::ReplicationGroup` | ElastiCache | E1 |
| `AWS::OpenSearchService::Domain` / `AWS::Elasticsearch::Domain` | OpenSearch | E2 |
| `AWS::S3::Bucket` | S3 | F1 (often "no alarm needed") |
| `AWS::CloudHSM::Cluster` / `AWS::CloudHSMV2::Cluster` | — | G1 (not covered — log/state monitoring) |

Resource types not in this table have no defined baseline tier — note them as "reviewed, no baseline tier defined" rather than inventing alarms.

## Reading Properties for size-dependent thresholds
Pull these from `Properties` so thresholds are grounded (Guardrail 4):
- EC2: `InstanceType` (burstable T-family → consider CPUCreditBalance).
- Lambda: `Timeout` (Duration alarm = ~80% of it), `ReservedConcurrentExecutions`.
- RDS: `AllocatedStorage` (FreeStorageSpace threshold), `DBInstanceClass` (connection limit).
- ElastiCache: `CacheNodeType`, `Engine` (Redis vs Memcached changes which metrics apply).
- OpenSearch: `EBSOptions.VolumeSize`, `ClusterConfig.InstanceCount`.

## Bonus: the alarms themselves may be in the template
Scan for `AWS::CloudWatch::Alarm` resources in the same template. If the stack already defines alarms for a resource, that is **existing coverage declared in IaC** — do not flag it as a gap. This is the one case where you can confirm coverage pre-deploy without `describe-alarms`: the alarm is right there in the template. Match the alarm's `Dimensions` to the resource.

## Important: these are intended resources, not deployed ones
A template describes what *will* exist after the stack deploys. Except for any `AWS::CloudWatch::Alarm` resources declared in the same template, the resources do not exist yet, so `describe-alarms` will find nothing — which is correct for a pre-deploy review. Treat each reviewed resource as a coverage gap unless an alarm for it is declared in the template or the customer says coverage is managed elsewhere.
