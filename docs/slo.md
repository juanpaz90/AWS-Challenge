# Service Level Objectives — Notes API

> Implemented as Prometheus recording and alert rules in `observability/` (Phase 10). Story: S7.

## SLIs

All SLIs are measured at the API from the `http_requests_total` and `http_request_duration_seconds` metrics exposed on `/metrics`. Health and metrics endpoints (`/healthz`, `/readyz`, `/metrics`) are **excluded**.

| SLI | Definition |
|---|---|
| Availability | `good = requests with status < 500` / `valid = all requests` |
| Latency | `good = requests completed in ≤ 300 ms` / `valid = all requests` |

## SLOs

| SLO | Target | Window | Error budget |
|---|---|---|---|
| Availability | **99.5%** of requests succeed | 30 days rolling | 0.5% of requests ≈ **3h 36m** of full outage per 30 days |
| Latency | **95%** of requests ≤ **300 ms** (p95 < 300 ms) | 30 days rolling | 5% of requests may exceed 300 ms |

### Why these numbers

- **99.5%** fits a single-region service with an in-cluster database: one DB instance locally and a 3-instance CNPG cluster on AWS. Aiming higher (99.9%) would need multi-AZ guarantees we don't test end to end yet.
- **300 ms p95** is comfortable for simple CRUD on a small dataset; it leaves headroom for DB round trips and TLS at the gateway.

## Error budget policy

| Budget remaining | Action |
|---|---|
| > 50% | Normal delivery. |
| 25–50% | Review recent changes; prioritise reliability items in the next iteration. |
| < 25% | Only low-risk changes; every deploy needs a tested rollback. |
| Exhausted | Freeze feature releases until the budget recovers; reliability work only; write a post-incident review. |

## Alerting on the SLO

Multi-window, multi-burn-rate alerts (Google SRE workbook pattern):

| Severity | Burn rate | Long window | Short window | Budget consumed if sustained |
|---|---|---|---|---|
| page (critical) | 14.4× | 1h | 5m | 2% in 1h |
| page (critical) | 6× | 6h | 30m | 5% in 6h |
| ticket (warning) | 1× | 3d | 6h | 10% in 3d |

Locally these will rarely fire on their own; they are demonstrated with induced failures (see the [runbook](runbook.md)).

## Example recording rules (sketch)

```promql
# Error ratio over 5m
sum(rate(http_requests_total{job="notes-api",status=~"5..",handler!~"/healthz|/readyz|/metrics"}[5m]))
/
sum(rate(http_requests_total{job="notes-api",handler!~"/healthz|/readyz|/metrics"}[5m]))

# p95 latency over 5m
histogram_quantile(0.95,
  sum by (le) (rate(http_request_duration_seconds_bucket{job="notes-api",handler!~"/healthz|/readyz|/metrics"}[5m])))
```

> Metric and label names are finalised once the instrumentation library is chosen in Phase 4.
