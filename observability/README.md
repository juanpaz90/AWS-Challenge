# Observability as code

Story S7 · [ADR-0006](../docs/adr/0006-observability-stack.md) · [SLOs](../docs/slo.md) · [Runbook](../docs/runbook.md)

| Path | What | Deployed by |
|---|---|---|
| `rules/notes-api.rules.yaml` | SLO recording rules (5m → 3d windows) and 7 alerts | `30-apps` as a `PrometheusRule` |
| `rules/tests/notes-api.test.yaml` | promtool unit tests (fires / stays quiet, PVC fallback, empty-vs-zero ratios) | `task obs:test`, pre-commit |
| `dashboards/notes-api.json` | Grafana dashboard *Notes API* (uid `notes-api`): SLO stats, request rate, error ratio vs budget, latency percentiles, replicas/HPA, CPU, DB connections, restarts, DB size, logs | `30-apps` as a ConfigMap labelled `grafana_dashboard=1` |

The platform side (Prometheus, Alertmanager, Grafana, Loki, Alloy, datasources) is installed by `20-platform`.

```bash
task obs:test     # promtool check + unit tests (same Prometheus version as the cluster)
task obs:check    # live: rules healthy, dashboard served, k6 load visible in every panel query,
                  # logs searchable, induced outage fires NotesApiDown and resolves
```

## Conventions

- Rule files stay **plain Prometheus format** so promtool tests exactly what is deployed; Terraform wraps them in a `PrometheusRule`.
- Every alert has `severity`, `service`, `summary`, `description` and a `runbook_url` that resolves to a section of `docs/runbook.md`.
- Ratios guard against missing series: a counter that has never been incremented does not exist, so numerators use `or vector(0)` (zero errors → 0, not "No data"), while no traffic at all still yields no value.
- The dashboard is generated JSON with fixed datasource UIDs (`prometheus`, `loki`) provisioned by `20-platform`; edit it in Grafana, export, and commit, or edit the JSON directly.

## Known local limitations

- kind's local-path volumes report no kubelet volume stats; `NotesDbPvcUsageHigh` falls back to PostgreSQL's database size ÷ PVC request (an underestimate). On EKS (EBS) the kubelet stats are used.
- Prometheus keeps 24 h locally, so the 3-day burn-rate window only sees what is retained.
- Alertmanager has no receiver configured locally; alerts are visible in Alertmanager and Grafana. A real receiver (Slack/PagerDuty via a Secret) is part of the AWS work.
