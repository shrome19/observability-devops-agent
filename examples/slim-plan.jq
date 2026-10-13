# slim-plan.jq — shrink a full `terraform show -json` plan into a sub-10K payload
# the DevOps Agent can accept (run-input field and webhook event triggers both
# cap input at 10,000 characters).
#
# Keeps only: created resources, their address/type, and the size/capacity fields
# the alarm-recommendation skill actually needs. Drops after_unknown,
# sensitive_values, and the configuration block (none affect alarm sizing).
#
# Usage:
#   terraform show -json tfplan | jq -f slim-plan.jq > slim-payload.json
#
# Then paste slim-payload.json into a manual agent run, OR have your pipeline
# POST it to the agent's webhook event trigger (see custom-agent/README.md).

{
  eventType: "deployment",
  action: "create",
  source: "terraform",
  # best-effort stack label; override in your pipeline if you have a real name
  stack: (.resource_changes[0].name // "unknown"),
  region: "us-east-1",
  resources: [
    .resource_changes[]
    | select(.change.actions | index("create"))
    | {
        address: .address,
        type: .type,
        action: "create",
        # whitelist only sizing-relevant fields across all supported tiers;
        # with_entries drops the keys that are null for this resource type
        config: (.change.after | {
          identifier, engine, engine_version, instance_class, allocated_storage,
          function_name, runtime, memory_size, timeout,
          name, load_balancer_type,
          node_type, num_cache_nodes,
          instance_type,
          volume_size,
          tags
        } | with_entries(select(.value != null)))
      }
  ]
}
