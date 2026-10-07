# E2 — OpenSearch Service Baseline Alarm Recommendations

## Goal
Recommend the minimum CloudWatch alarms an Amazon OpenSearch Service domain should have before deployment.

## Confirm the resource
```
aws opensearch describe-domain --domain-name <name> --query 'DomainStatus.{Name:DomainName,Arn:ARN,Instances:ClusterConfig.InstanceCount,Type:ClusterConfig.InstanceType,EBS:EBSOptions.VolumeSize}'
```
OpenSearch metrics use the `DomainName` + `ClientId` (account ID) dimensions. Note the EBS volume size — the FreeStorageSpace threshold derives from it.

## Check existing coverage
```
aws cloudwatch describe-alarms --query "MetricAlarms[?Namespace=='AWS/ES'].{Name:AlarmName,Metric:MetricName,Dim:Dimensions}"
```
Note: the CloudWatch namespace is `AWS/ES` (the legacy Elasticsearch name), not `AWS/OpenSearch`. A gap exists if no alarm has a `DomainName` dimension matching this domain.

## Recommended baseline

| Alarm | Metric (AWS/ES) | Statistic | Threshold | Comparison | Eval | Why |
|-------|-----------------|-----------|-----------|-----------|------|-----|
| Cluster status red | ClusterStatus.red | Maximum | 1 | >= | 1×60s | At least one primary shard unallocated → data unavailable |
| Cluster status yellow | ClusterStatus.yellow | Maximum | 1 | >= | 5×60s, 3 datapoints | Replica shards unallocated → reduced resiliency |
| JVM memory pressure | JVMMemoryPressure | Maximum | 85% | >= | 3×60s, 2 datapoints | Sustained high heap → GC pauses, node instability |
| Free storage low | FreeStorageSpace | Minimum | ~20% of per-node EBS (MiB) | <= | 1×60s | Storage exhaustion → cluster blocks writes |
| Writes blocked | ClusterIndexWritesBlocked | Maximum | 1 | >= | 1×300s | Cluster has blocked index writes (disk/memory/other) |

Notes:
- `ClusterStatus.red` is the must-have — it means data is unavailable. Alarm on it fast (1 datapoint).
- `FreeStorageSpace` on OpenSearch is reported in **MiB** per data node, and is a size-dependent threshold (see Guardrail 4): derive from the domain's per-node EBS volume size, do not hardcode.
- `JVMMemoryPressure` sustained above ~85% is the leading indicator of heap trouble; brief spikes are normal (hence multiple datapoints).
- `TreatMissingData`: `notBreaching` (missing data usually means the domain is reporting fine, not failing — except red status, which is rare enough to review manually).

## Maps to
`recommended-alarms.yaml` → set `OpenSearchDomainName` to enable the OpenSearch tier (creates `-opensearch-status-red`, `-opensearch-jvm-pressure`, `-opensearch-free-storage-low`).
