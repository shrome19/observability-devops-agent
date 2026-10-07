# F1 — S3 Baseline Alarm Recommendations

## Goal
Recommend the minimum CloudWatch alarms an S3-backed app should have before deployment — with an honest note that many S3 buckets need **no** operational alarm.

## When S3 alarms are warranted (and when they are not)
S3 is a managed, highly available service, so a plain object store rarely needs CloudWatch alarms. Recommend S3 alarms only when the bucket is on a request path the app depends on (e.g. serving assets, an upload pipeline, a data lake landing zone). For a passive backup/archive bucket, the honest recommendation is usually "no alarm needed" — say so rather than inventing coverage (see Guardrail 9: do not over-alarm).

## Confirm the resource
```
aws s3api get-bucket-location --bucket <name>
aws s3api get-bucket-metrics-configuration --bucket <name> --id EntireBucket 2>/dev/null || echo "No request-metrics configuration — 4xx/5xx/latency alarms require one"
```

## Check existing coverage
```
aws cloudwatch describe-alarms --query "MetricAlarms[?Namespace=='AWS/S3'].{Name:AlarmName,Metric:MetricName,Dim:Dimensions}"
```
A gap exists only if the bucket is request-path-critical AND has no alarm on its request metrics.

## Recommended baseline (request-path-critical buckets only)

| Alarm | Metric (AWS/S3) | Statistic | Threshold | Comparison | Eval | Why |
|-------|-----------------|-----------|-----------|-----------|------|-----|
| 5xx errors | 5xxErrors | Average | 0.01 (1%) | >= | 3×60s, 2 datapoints | S3-side errors on a dependency path → app failures |
| 4xx errors | 4xxErrors | Average | tune to baseline | >= | 5×60s, 3 datapoints | Spike in client errors → broken keys/permissions after deploy |
| Request latency | TotalRequestLatency | Average | tune to baseline (ms) | >= | 3×60s, 2 datapoints | Latency regression on a critical object path |

Notes:
- **Request metrics (`4xxErrors`, `5xxErrors`, `TotalRequestLatency`) are NOT emitted by default.** They require a bucket **request-metrics configuration** (a filter ID, e.g. `EntireBucket`), which is also a paid CloudWatch feature. If it is not configured, these alarms cannot fire — recommend enabling request metrics first, or do not recommend these alarms (Guardrail 5: confirm the metric is actually published).
- Storage metrics (`BucketSizeBytes`, `NumberOfObjects`) are daily and free, but they are capacity-trend signals, not operational alarms — not part of the pre-deploy baseline.
- `TreatMissingData`: `notBreaching`.

## Maps to
`recommended-alarms.yaml` → set `S3BucketName` to enable the S3 tier (creates `-s3-5xx-high`). Only enable this tier for request-path-critical buckets that have request metrics configured.
