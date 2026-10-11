# ADR-0006: Observability stack — in-cluster Grafana, Loki and Alloy

- **Status:** Accepted
- **Date:** 2026-10-11
- **Related:** S7

## Context

We need metrics, logs, dashboards, alerts and SLOs, all defined as code and working the same way locally and on EKS. The log shipper choice matters: **Promtail is deprecated** (in favour of Grafana Alloy) and reached end of life in early 2026.

Constraints: laptop memory (Docker ≥ 8 GB), and the platform must not depend on a SaaS account.

## Decision

Install the observability stack **in-cluster** via Helm in `20-platform`, in the `monitoring` namespace:

| Concern | Component |
|---|---|
| Metrics, alerts, dashboards | **kube-prometheus-stack** (Prometheus Operator, Prometheus, Alertmanager, Grafana, kube-state-metrics, node-exporter) |
| Logs | **Loki** in single-binary mode, filesystem storage locally |
| Log collection | **Grafana Alloy** (DaemonSet) |
| App metrics discovery | `ServiceMonitor` shipped in the Notes API chart |

As-code conventions:

- Datasources (Prometheus, Loki) are provisioned through Helm values.
- Dashboards live as JSON in `observability/dashboards/` and are loaded through the Grafana sidecar (labelled ConfigMaps).
- Alert rules live as `PrometheusRule` resources in `observability/alerts/`.
- SLOs are defined in [`slo.md`](../slo.md) and implemented as recording rules.
- Grafana is exposed at `grafana.localtest.me` through the shared Gateway; the admin password is generated in-cluster, not set in values.

Local sizing: short Prometheus retention (e.g. 24h), single replicas, and reduced resource requests.

`grafana/otel-lgtm` (all-in-one Docker container) is used **only** for quick telemetry checks during Phase 4 Docker Compose testing, never as the platform.

## Alternatives considered

| Option | Pros | Cons | Why not chosen |
|---|---|---|---|
| Promtail for logs | Familiar | Deprecated / EOL | Not acceptable for new work |
| Grafana Cloud / SaaS | No resource usage | External account, network dependency, not reproducible offline | Breaks local-first and "as code" demos |
| Amazon Managed Prometheus/Grafana | Managed on AWS | No local equivalent | Breaks local ≈ cloud |
| ELK / OpenSearch | Powerful search | Very heavy for a laptop | Resource cost |

## Consequences

**Positive**

- Identical observability locally and on EKS; dashboards and alerts are versioned.
- Standard, widely known tooling.

**Negative / trade-offs**

- Highest memory consumer of the local stack.
- Local Loki and Prometheus data is ephemeral (acceptable).

**Follow-ups**

- On AWS: Loki object storage on S3 via Pod Identity; consider AMP/AMG as a managed option.
