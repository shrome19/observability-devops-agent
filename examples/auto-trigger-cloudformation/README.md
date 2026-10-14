# CloudFormation / CDK auto-trigger (CI-free)

Reference infrastructure that fires the Observability Agent automatically when a
**CloudFormation or CDK** stack finishes deploying — with **no CI tool involved**.
CloudFormation emits a stack-status event to EventBridge natively; a Lambda reads the
stack's resources, builds a slim payload, signs it, and POSTs it to the agent webhook.

This is the counterpart to the Terraform pipeline hook (`../pipeline/`). Together they
cover both deployment paths the demo needs:

| Deploy via | Trigger mechanism | CI tool needed? |
|------------|-------------------|-----------------|
| **CloudFormation / CDK** | EventBridge `CloudFormation Stack Status Change` → Lambda → webhook | **No** — event-native |
| **Terraform** | pipeline step runs `review-alarms.sh` → webhook | Yes — any CI (Terraform emits no AWS deploy event) |

Both POST the **same slim payload shape** to the **same agent webhook** and sign it the
**same way** (HMAC-SHA256 over `<timestamp>:<body>`), so the agent side is identical.

## Flow

```
CFN/CDK stack reaches CREATE_COMPLETE or UPDATE_COMPLETE
   │  EventBridge rule (source: aws.cloudformation)       ← no CI tool
   ▼
Lambda (observability-agent-cfn-trigger)
   1. reads detail.stack-id from the event
   2. cloudformation:DescribeStackResources → resource list
   3. keeps only alarm-tier resource types (EC2/Lambda/RDS/ALB/ElastiCache/OpenSearch/S3)
   4. builds slim payload, HMAC-signs, POSTs to the webhook
   ▼
pre-deploy-observability-reviewer  →  loads skill  →  CloudWatch coverage recommendations
                                                       (in the agent's run history)
```

## Deploy

```bash
# 1. Put the webhook secret in Secrets Manager (plain string value)
aws secretsmanager create-secret \
  --name observability-agent-webhook-secret \
  --secret-string 'YOUR_WEBHOOK_SHARED_SECRET'

# 2. Deploy this template
aws cloudformation deploy \
  --template-file template.yaml \
  --stack-name observability-agent-cfn-trigger \
  --capabilities CAPABILITY_NAMED_IAM \
  --parameter-overrides \
      WebhookUrl='https://connect.aidevops.us-east-1.api.aws/.../webhook' \
      WebhookSecretArn='arn:aws:secretsmanager:us-east-1:ACCOUNT:secret:observability-agent-webhook-secret-XXXX' \
      ExcludeStackName='observability-agent-cfn-trigger'   # ignore its own deploy
```

Set `ExcludeStackName` to this stack's own name so the trigger does not react to
deploying itself.

## Test end-to-end

Deploy any small CFN stack (e.g. the `../sample-cloudformation/sample-stack.yaml`), let
it reach `CREATE_COMPLETE`, then check the agent's run history for a coverage review of
that stack's resources.

## Caveats (verify before relying on this)

- **This is reference code, not deployed by this repo.** Review the IAM and the
  outbound POST against your account's policies first.
- **Egress guardrails.** The Lambda makes an outbound HTTPS POST to the agent webhook.
  The same account guardrails that blocked Lambda Function URLs earlier in this project
  could affect outbound calls — confirm egress is allowed.
- **10,000-char cap.** The Lambda filters to alarm-tier resources and sends physical
  IDs only, so payloads stay tiny. A stack with a very large number of tier resources
  could still approach the cap — chunk if needed.
- **Timing is post-complete.** This reviews resources that just went live (reactive).
  For a true pre-deploy gate on CFN, trigger on change-set creation instead and review
  the template — more wiring, not covered here.
- **Event shape** (`detail.status-details.status`, `detail.stack-id`) is from the AWS
  CloudFormation EventBridge docs. Confirm against a real event in your account.
