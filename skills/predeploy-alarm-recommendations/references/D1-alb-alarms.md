# D1 — ALB Baseline Alarm Recommendations

## Goal
Recommend the minimum CloudWatch alarms an ALB-fronted app should have before deployment.

## Confirm the resource
```
aws elasticloadbalancing describe-load-balancers --query 'LoadBalancers[*].{Name:LoadBalancerName,Arn:LoadBalancerArn,DNS:DNSName}'
```
The `LoadBalancer` dimension value is the ARN suffix: the `app/<name>/<id>` tail of the ARN.

## Check existing coverage
```
aws cloudwatch describe-alarms --query "MetricAlarms[?Namespace=='AWS/ApplicationELB'].{Name:AlarmName,Metric:MetricName,Dim:Dimensions}"
```
A gap exists if no alarm has a `LoadBalancer` dimension matching this ALB.

## Recommended baseline

| Alarm | Metric (AWS/ApplicationELB) | Statistic | Threshold | Comparison | Eval | Why |
|-------|-----------------------------|-----------|-----------|-----------|------|-----|
| 5xx errors | HTTPCode_ELB_5XX_Count | Sum | 10 | >= | 2×60s | Backend unhealthy / load balancer errors |
| Target latency | TargetResponseTime | p95 | 1s | >= | 3×60s, 2 datapoints | Backend slow → user-facing degradation |
| Unhealthy hosts | UnHealthyHostCount | Maximum | 1 | >= | 2×60s | Targets failing health checks |

Notes:
- `HTTPCode_ELB_5XX_Count` is errors from the ALB itself; `HTTPCode_Target_5XX_Count` is from the targets. Recommend the ELB one as the baseline, and the Target one when the app returns its own 5xx.
- TargetResponseTime uses an extended statistic (p95) — use `ExtendedStatistic`, not `Statistic`.
- `TreatMissingData`: `notBreaching` (no traffic is not a failure).

## Maps to
`recommended-alarms.yaml` → set `AlbArnSuffix` to enable the ALB tier (creates `-alb-5xx-high` and `-alb-target-latency-high`).
