# A1 — EC2 Baseline Alarm Recommendations

## Goal
Recommend the minimum CloudWatch alarms an EC2-backed app should have before deployment.

## Confirm the resource
```
aws ec2 describe-instances --instance-ids <id> --query 'Reservations[*].Instances[*].{Id:InstanceId,Type:InstanceType,State:State.Name}'
```

## Check existing coverage
```
aws cloudwatch describe-alarms --query "MetricAlarms[?Namespace=='AWS/EC2'].{Name:AlarmName,Metric:MetricName,Dim:Dimensions}"
```
A gap exists if no alarm has a `InstanceId` dimension matching this instance.

## Recommended baseline

| Alarm | Metric (AWS/EC2) | Statistic | Threshold | Comparison | Eval | Why |
|-------|------------------|-----------|-----------|-----------|------|-----|
| CPU high | CPUUtilization | Average | 80% (prod) / 90% (dev) | >= | 3×60s, 2 datapoints | Runaway load, undersized instance |
| Status check failed | StatusCheckFailed | Maximum | 1 | >= | 2×60s | Instance/system impaired, unreachable |

Notes:
- For T-family (burstable) instances, also consider `CPUCreditBalance` low — sustained load can exhaust credits and throttle the instance.
- `TreatMissingData`: use `breaching` for StatusCheckFailed (missing data often means the instance is down), `notBreaching` for CPU.

## Maps to
`recommended-alarms.yaml` → set `Ec2InstanceId` to enable the EC2 tier (creates `-ec2-cpu-high` and `-ec2-status-check-failed`).
