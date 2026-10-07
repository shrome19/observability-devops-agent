# Pre-Deployment Alarm Recommendation Guardrails

Read these guardrails BEFORE finalizing any pre-deploy alarm recommendation.

## Guardrail 1: This Is Advisory, Not Action
This skill recommends alarms. It never creates or modifies them. Never state or imply that alarms were created. Deployment is a separate, explicit step the customer takes (via the companion `recommended-alarms.yaml`).

## Guardrail 2: Verify Before Claiming a Gap
Only call something a "coverage gap" after running `cloudwatch describe-alarms` and confirming no alarm references that resource's dimension. Do not assume alarms are missing from the absence of a manifest entry.

## Guardrail 3: Thresholds Are Starting Points
Every recommended threshold is a baseline to be tuned to the workload, not a guaranteed-correct value. Always say so. A "CPU >= 80%" recommendation is a sane default, not a fact about this app's healthy range.

## Guardrail 4: Size-Dependent Thresholds Require the Resource's Config
FreeStorageSpace depends on AllocatedStorage. DatabaseConnections depends on the instance class's max_connections. Duration depends on the function Timeout. Never emit a hard number for these without first reading the resource's configuration.

## Guardrail 5: Confirm the Metric Is Actually Published
Recommend an alarm only for a metric that the resource actually emits. For example, custom application metrics will not exist until the app publishes them. Use `cloudwatch list-metrics` to confirm when unsure.

## Guardrail 6: Extended Statistics Use a Different Field
Percentile-based alarms (p95, p99) use `ExtendedStatistic`, not `Statistic`. Recommending TargetResponseTime p95 with `Statistic: p95` is invalid and will fail to deploy.

## Guardrail 7: TreatMissingData Matters
"No data" is not always "healthy." StatusCheckFailed missing usually means the instance is down (treat as breaching). Lambda Errors missing means no invocations (treat as not breaching). Recommend the correct missing-data behavior per alarm.

## Guardrail 8: Enrichment Requires Evidence
When you recommend an alarm "because of a past incident," cite the specific CloudTrail event or prior investigation. Never claim historical incidents without evidence.

## Guardrail 9: Do Not Over-Alarm
Recommending an alarm on every available metric creates noise the team will mute. Recommend the baseline that maps to real, actionable failure modes. Distinguish "must have before deploy" from "nice to have."

## Guardrail 10: Regional and Dimensional Correctness
Alarms are regional and dimension-specific. Recommend alarms in the same region as the resource, with the exact dimension value (InstanceId, FunctionName, DBInstanceIdentifier, LoadBalancer ARN suffix). A wrong dimension produces an alarm that never fires.
