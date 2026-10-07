# E1 — ElastiCache Baseline Alarm Recommendations

## Goal
Recommend the minimum CloudWatch alarms an ElastiCache-backed app (Redis or Memcached) should have before deployment.

## Confirm the resource
```
aws elasticache describe-cache-clusters --show-cache-node-info --query 'CacheClusters[*].{Id:CacheClusterId,Engine:Engine,NodeType:CacheNodeType,Status:CacheClusterStatus}'
```
For Redis (cluster mode), node-level metrics use the `CacheClusterId` + `CacheNodeId` dimensions. Note the engine — some metrics (e.g. `DatabaseMemoryUsagePercentage`, `Evictions`) are Redis-specific.

## Check existing coverage
```
aws cloudwatch describe-alarms --query "MetricAlarms[?Namespace=='AWS/ElastiCache'].{Name:AlarmName,Metric:MetricName,Dim:Dimensions}"
```
A gap exists if no alarm has a `CacheClusterId` dimension matching this cluster.

## Recommended baseline

| Alarm | Metric (AWS/ElastiCache) | Statistic | Threshold | Comparison | Eval | Why |
|-------|--------------------------|-----------|-----------|-----------|------|-----|
| Engine CPU high | EngineCPUUtilization | Average | 90% | >= | 3×60s, 2 datapoints | Redis is single-threaded; engine CPU saturation stalls commands (prefer over host CPUUtilization) |
| Memory pressure | DatabaseMemoryUsagePercentage | Average | 85% | >= | 3×60s, 2 datapoints | Approaching maxmemory → evictions or OOM (Redis) |
| Evictions | Evictions | Sum | > 0 (tune to workload) | >= | 5×60s, 3 datapoints | Keys being evicted under memory pressure; cache effectiveness dropping |
| Connections high | CurrConnections | Average | ~80% of node connection limit | >= | 3×60s, 2 datapoints | Connection leak / pool exhaustion |

Notes:
- Prefer `EngineCPUUtilization` over `CPUUtilization` for Redis: the engine runs on one thread, so host CPU can look low while the engine is saturated. For Memcached (multi-threaded), `CPUUtilization` is the right CPU signal.
- `DatabaseMemoryUsagePercentage` is Redis-only. For Memcached, use `FreeableMemory` (low) instead.
- Eviction threshold is workload-dependent — some caches evict by design. Start by alarming on any sustained evictions, then tune. This is a size/workload-dependent threshold (see Guardrail 4).
- `TreatMissingData`: `notBreaching` for all.

## Maps to
`recommended-alarms.yaml` → set `ElastiCacheClusterId` to enable the ElastiCache tier (creates `-elasticache-engine-cpu-high`, `-elasticache-memory-high`, `-elasticache-evictions`).
