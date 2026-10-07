# G1 — CloudHSM: Not Covered by the Baseline (Deliberate)

## Why there is no CloudHSM alarm tier
CloudHSM is intentionally **excluded** from the pre-deploy alarm baseline. This is not an oversight — it is the anti-hallucination rules applied honestly.

CloudHSM exposes a very limited set of CloudWatch metrics in the `AWS/CloudHSM` namespace (and in many account/cluster configurations, none that map cleanly to a generic operational threshold the way EC2 CPU or RDS storage do). There is no credible, widely-documented "deploy this alarm with this threshold" baseline for CloudHSM the way there is for compute, serverless, database, cache, and search tiers. Inventing thresholds for it would violate Guardrail 3 (thresholds are starting points, not fabrications) and the anti-hallucination rule "recommend alarms only for metrics the resource actually emits."

## What to recommend instead
When a review encounters a CloudHSM cluster, do NOT fabricate CloudWatch alarms. Instead, state plainly:

- CloudHSM health and audit are primarily observed through **CloudHSM audit logs** (delivered to CloudWatch Logs) and the **cluster/HSM state via the API** (`aws cloudhsmv2 describe-clusters`), not through threshold alarms.
- Recommend confirming audit logging is enabled and that cluster state is monitored operationally.
- If the account has a specific, verified CloudHSM metric being published, an alarm on that specific metric can be considered — but only after confirming it exists with `aws cloudwatch list-metrics --namespace AWS/CloudHSM`.

## Confirm the resource (for context, not for alarming)
```
aws cloudhsmv2 describe-clusters --query 'Clusters[*].{Id:ClusterId,State:State,Hsms:Hsms[*].State}'
aws cloudwatch list-metrics --namespace AWS/CloudHSM
```
If `list-metrics` returns nothing, there is nothing to alarm on — say so.

## Maps to
Nothing in `recommended-alarms.yaml`. CloudHSM is deliberately out of scope for the deployable baseline; the honest recommendation is log/state-based monitoring, not a fabricated alarm tier.
