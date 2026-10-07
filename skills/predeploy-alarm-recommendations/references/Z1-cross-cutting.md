# Z1 — Cross-Cutting Recommendations

Applies across all resource tiers when producing a pre-deploy alarm recommendation.

## Severity by environment
Map environment to alarm priority so prod pages and dev does not:
- `prod` → CRITICAL: wire to a notification channel (SNS → PagerDuty/Slack/email).
- `uat` → MEDIUM: notify a team channel.
- `dev` → LOW: alarms exist for auto-investigation but need not page.

The companion template takes an `Environment` parameter that stamps an `env` tag on every alarm; the alarm-ingestion pipeline maps that tag to priority.

## Tag every alarm for auto-investigation
Recommend tagging alarms with `auto_investigate=true` so that when they DO fire, the alarm-ingestion pipeline forwards them to the DevOps Agent automatically. This closes the loop: proactive alarms now, automatic investigation later. Also tag `env=<environment>`.

## Wire notifications (optional but recommended)
Alarms with no action still change state and still feed auto-investigation, but a human sees nothing in real time. Recommend an SNS topic as the `AlarmActions` target for prod. The companion template accepts an optional `AlarmTopicArn`.

## Synthesize the coverage gap summary
End every review with a short summary:
- Resources reviewed (count by type).
- Resources with ZERO existing alarms (the real gaps).
- Recommended alarms, grouped by tier, each with metric/threshold/rationale.
- Any alarm recommended specifically because of a PAST incident in this account (cite it).
- The exact `recommended-alarms.yaml` parameters to deploy the recommended tiers.

## Do not over-alarm
More alarms is not better. Recommend the baseline that catches real failure modes; avoid alarms on metrics the team cannot act on. Note when an alarm is "nice to have" vs "must have before deploy."
