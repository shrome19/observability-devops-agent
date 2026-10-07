# C1 — RDS Baseline Alarm Recommendations

## Goal
Recommend the minimum CloudWatch alarms an RDS-backed app should have before deployment.

## Confirm the resource
```
aws rds describe-db-instances --db-instance-identifier <id> --query 'DBInstances[*].{Id:DBInstanceIdentifier,Class:DBInstanceClass,Storage:AllocatedStorage,MaxConn:PendingModifiedValues}'
```
Note `AllocatedStorage` (GiB) — the FreeStorageSpace threshold must be derived from it, not hardcoded blindly.

## Check existing coverage
```
aws cloudwatch describe-alarms --query "MetricAlarms[?Namespace=='AWS/RDS'].{Name:AlarmName,Metric:MetricName,Dim:Dimensions}"
```
A gap exists if no alarm has a `DBInstanceIdentifier` dimension matching this instance.

## Recommended baseline

| Alarm | Metric (AWS/RDS) | Statistic | Threshold | Comparison | Eval | Why |
|-------|------------------|-----------|-----------|-----------|------|-----|
| CPU high | CPUUtilization | Average | 80% | >= | 5×60s, 3 datapoints | Slow queries, undersized instance |
| Free storage low | FreeStorageSpace | Average | ~15% of AllocatedStorage (bytes) | <= | 1×300s | Storage exhaustion → DB goes read-only |
| Connections high | DatabaseConnections | Average | ~80% of max_connections | >= | 3×60s, 2 datapoints | Connection leak / pool exhaustion |

Notes:
- FreeStorageSpace threshold: convert a percentage of AllocatedStorage to bytes (GiB × 1073741824). The companion template defaults to 5 GiB — adjust per instance.
- max_connections scales with instance class (roughly memory-based). Verify before setting a hard number.
- `TreatMissingData`: `notBreaching` for all three.

## Maps to
`recommended-alarms.yaml` → set `RdsInstanceId` to enable the RDS tier (creates `-rds-cpu-high`, `-rds-free-storage-low`, `-rds-connections-high`).
