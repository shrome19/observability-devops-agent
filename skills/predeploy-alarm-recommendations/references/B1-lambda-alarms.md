# B1 — Lambda Baseline Alarm Recommendations

## Goal
Recommend the minimum CloudWatch alarms a Lambda-backed app should have before deployment.

## Confirm the resource
```
aws lambda get-function-configuration --function-name <name> --query '{Name:FunctionName,Timeout:Timeout,Memory:MemorySize,Concurrency:ReservedConcurrentExecutions}'
```
Note the `Timeout` — the Duration alarm threshold should be a fraction of it.

## Check existing coverage
```
aws cloudwatch describe-alarms --query "MetricAlarms[?Namespace=='AWS/Lambda'].{Name:AlarmName,Metric:MetricName,Dim:Dimensions}"
```
A gap exists if no alarm has a `FunctionName` dimension matching this function.

## Recommended baseline

| Alarm | Metric (AWS/Lambda) | Statistic | Threshold | Comparison | Eval | Why |
|-------|---------------------|-----------|-----------|-----------|------|-----|
| Errors | Errors | Sum | 1 | >= | 1×60s | Any error indicates broken invocations (bad config, code, deps) |
| Throttles | Throttles | Sum | 1 | >= | 1×60s | Concurrency limit or account limit hit |
| Duration near timeout | Duration | Maximum | 80% of Timeout (ms) | >= | 3×60s, 2 datapoints | Approaching timeout → imminent failures |

Notes:
- Errors and Throttles are the two must-haves — they map to the two most common Lambda incidents (poisoned config/code, concurrency starvation).
- Duration is optional but valuable: it catches slow degradation before it becomes timeouts.
- `TreatMissingData`: `notBreaching` for all three (no invocations is not a failure).

## Maps to
`recommended-alarms.yaml` → set `LambdaFunctionName` to enable the Lambda tier (creates `-lambda-errors` and `-lambda-throttles`).
