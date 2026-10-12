# notes-api

![Version: 0.1.0](https://img.shields.io/badge/Version-0.1.0-informational?style=flat-square) ![AppVersion: 0.1.0](https://img.shields.io/badge/AppVersion-0.1.0-informational?style=flat-square)

Notes API (FastAPI + PostgreSQL) — hardened Deployment with probes, HPA, PDB, NetworkPolicies, Gateway API route and Alembic migration hook

Story S4. Deployed by Terraform in `infra/environments/<env>/30-apps` (Phase 8), later by Argo CD (Phase 12).

## What it renders

| Resource | Notes |
|---|---|
| `Deployment` | Startup/liveness/readiness probes, `preStop` sleep then graceful drain, `maxUnavailable: 0` rollouts, topology spread (`nodeTaintsPolicy: Honor`), Pod Security `restricted`, read-only root FS with an `emptyDir` `/tmp`, config checksum annotation so config changes roll the pods |
| `Service` | `ClusterIP` only (the schema rejects anything else) |
| `HTTPRoute` | Attaches to the shared Gateway's HTTPS listener (toggle `httpRoute.enabled`) |
| `ConfigMap` | Non-secret settings only |
| — | **No Secret.** Database credentials are referenced from `database.existingSecret` (CloudNativePG's `<cluster>-app`) |
| `HorizontalPodAutoscaler`, `PodDisruptionBudget` | CPU-based scaling; `unhealthyPodEvictionPolicy: AlwaysAllow` so a broken pod never blocks a drain |
| `ServiceAccount` | Token not mounted (the API never calls the Kubernetes API) |
| `ServiceMonitor` | Scrapes `/metrics` every `serviceMonitor.interval` |
| `NetworkPolicy` ×4 | Namespace default-deny + DNS, API (in: Envoy + Prometheus; out: database), migration Job (out: database) |
| `Job` (hook) | `alembic upgrade head` as `pre-install,pre-upgrade`, before any new pod starts |

## Ownership boundary for network policies

The chart owns policies that select **its own pods** (plus the namespace baseline). Policies that select the **database pods** — including "allow this release → 5432" — belong to the database owner (`30-apps`), because the pre-install migration hook runs before any resource of this chart exists. The chart's pods carry `app.kubernetes.io/name: notes-api` and `app.kubernetes.io/instance: <release>` for that purpose.

## Usage

```bash
helm upgrade --install notes-api charts/notes-api --namespace notes \
  -f charts/notes-api/values-local.yaml \
  --set image.tag=<git-sha>
```

`image.tag` (or `image.digest`), `image.repository`, `database.existingSecret` and, with network policies on, `database.podSelector` are required; `values.schema.json` rejects mutable tags, non-`ClusterIP` services, root or writable-root containers and unknown keys.

| File | Environment |
|---|---|
| `values.yaml` | Defaults and documentation |
| `values-local.yaml` | kind: `localhost:5001` registry, `api.localtest.me`, small requests, fast HPA scale-in |
| `values-dev.yaml` | EKS dev: zone + host spread, repository/tag injected by Terraform/CI |
| `values-prod.yaml` | EKS prod: hard zone spread, 3–10 replicas, `minAvailable: 2` |
| `ci/validate-values.yaml` | Placeholders for offline validation only |

## Validation

```bash
task chart:lint    # helm lint + kubeconform for every overlay (scripts/validate-helm.sh)
task chart:test    # behavioural tests: tests/chart/test_notes_api_chart.py
task chart:docs    # regenerate this README (helm-docs)
```

Accepted `trivy config` findings (MEDIUM, below the HIGH/CRITICAL gate): **KSV-01010** is a name-based false positive on the ConfigMap keys (no credentials are stored there); **KSV-0125** flags the local/placeholder registry, which is ECR in AWS.

## Requirements

Kubernetes: `>=1.33.0-0`

## Values

| Key | Type | Default | Description |
|-----|------|---------|-------------|
| affinity | object | `{}` | Affinity rules. |
| autoscaling.enabled | bool | `true` | Create a HorizontalPodAutoscaler (requires metrics-server). |
| autoscaling.maxReplicas | int | `5` | Maximum replicas. |
| autoscaling.minReplicas | int | `2` | Minimum replicas. |
| autoscaling.scaleDownStabilizationSeconds | int | `120` | Seconds the HPA waits before scaling in (lower = faster demo, higher = less flapping). |
| autoscaling.targetCPUUtilizationPercentage | int | `70` | Target average CPU utilisation (% of requests). |
| config.appMessage | string | `"Hello from the Notes API"` | Message returned by `GET /`; change it to demo a rolling update. |
| config.dbMaxOverflow | int | `5` | Extra connections above the pool size per pod. |
| config.dbPoolSize | int | `5` | SQLAlchemy pool size per pod. |
| config.logLevel | string | `"INFO"` | Log level. |
| config.shutdownTimeoutSeconds | int | `20` | Seconds uvicorn waits for in-flight requests after SIGTERM. |
| containerPort | int | `8000` | Port the container listens on. |
| database.existingSecret | string | `""` | Existing Secret with the database credentials. The chart only **references** it; on CloudNativePG it is the operator-generated `<cluster>-app` Secret. |
| database.podSelector | object | `{}` | Labels selecting the database pods, used by the NetworkPolicies (CloudNativePG: `cnpg.io/cluster`). |
| database.port | int | `5432` | Database port, used by the NetworkPolicies. |
| database.secretKeys | object | `{"host":"host","name":"dbname","password":"password","port":"port","user":"username"}` | Keys inside `existingSecret` (defaults match CloudNativePG). |
| fullnameOverride | string | `""` | Override the full resource name. |
| httpRoute.enabled | bool | `true` | Create a Gateway API HTTPRoute. |
| httpRoute.hostnames | list | `[]` | Hostnames served by the route. |
| httpRoute.parentRefs | list | `[]` | Gateways the route attaches to. |
| image.digest | string | `""` | Optional digest (`sha256:...`); when set it is used instead of the tag. |
| image.pullPolicy | string | `"IfNotPresent"` | Image pull policy. |
| image.repository | string | `""` | Image repository (local registry, ECR, ...). Required. |
| image.tag | string | `""` | Immutable image tag (git SHA). Required; `latest` is rejected by the schema. |
| imagePullSecrets | list | `[]` | Pull secrets for private registries. |
| migration.activeDeadlineSeconds | int | `300` | Seconds before a stuck migration Job is killed. |
| migration.backoffLimit | int | `3` | Retries before the release fails. |
| migration.enabled | bool | `true` | Run `alembic upgrade head` as a Helm pre-install/pre-upgrade hook Job. |
| migration.resources | object | `{"limits":{"memory":"192Mi"},"requests":{"cpu":"50m","memory":"96Mi"}}` | Migration Job resources. |
| nameOverride | string | `""` | Override the chart name in resource names. |
| networkPolicy.dns | object | `{"namespace":"kube-system","podLabels":{"k8s-app":"kube-dns"}}` | DNS servers (egress allowed on 53/UDP+TCP). |
| networkPolicy.enabled | bool | `true` | Create NetworkPolicies (docs/architecture.md §3.2). |
| networkPolicy.gateway | object | `{"namespace":"gateway","podLabels":{"app.kubernetes.io/component":"proxy","app.kubernetes.io/name":"envoy"}}` | Who may call the API: the Gateway's Envoy proxies. |
| networkPolicy.monitoring | object | `{"namespace":"monitoring","podLabels":{"app.kubernetes.io/name":"prometheus"}}` | Who may scrape `/metrics`. |
| networkPolicy.namespaceDefaultDeny | bool | `true` | Default-deny ingress and egress for the **whole namespace**, plus DNS egress. Disable if the namespace owner already provides them. |
| nodeSelector | object | `{}` | Node selector. |
| podAnnotations | object | `{}` | Extra pod annotations. |
| podDisruptionBudget.enabled | bool | `true` | Create a PodDisruptionBudget. |
| podDisruptionBudget.minAvailable | int | `1` | Minimum pods available during voluntary disruptions (node drains, upgrades). |
| podLabels | object | `{}` | Extra pod labels. |
| podSecurityContext | object | `{"runAsGroup":10001,"runAsNonRoot":true,"runAsUser":10001,"seccompProfile":{"type":"RuntimeDefault"}}` | Pod security context (Pod Security Admission `restricted`). |
| preStopSleepSeconds | int | `5` | Seconds to keep serving after termination starts, so endpoints are removed from load balancers before the process stops accepting connections. |
| probes.liveness | object | `{"failureThreshold":3,"path":"/healthz","periodSeconds":10,"timeoutSeconds":2}` | Liveness probe: restarts the container if the process stops serving. |
| probes.readiness | object | `{"failureThreshold":2,"path":"/readyz","periodSeconds":5,"timeoutSeconds":3}` | Readiness probe: removes the pod from the Service while the database is unreachable. |
| probes.startup | object | `{"failureThreshold":30,"path":"/healthz","periodSeconds":2}` | Startup probe: gives the app up to failureThreshold × periodSeconds to start. |
| replicaCount | int | `2` | Pod replicas when the HPA is disabled. With the HPA enabled, the HPA owns the count. |
| resources | object | `{"limits":{"memory":"256Mi"},"requests":{"cpu":"100m","memory":"128Mi"}}` | Container resources. Requests drive scheduling and HPA utilisation; the memory limit protects the node. No CPU limit, to avoid throttling latency spikes. |
| securityContext | object | `{"allowPrivilegeEscalation":false,"capabilities":{"drop":["ALL"]},"readOnlyRootFilesystem":true}` | Container security context (Pod Security Admission `restricted`). |
| service.port | int | `80` | Service port. |
| service.type | string | `"ClusterIP"` | Service type. Only ClusterIP: the API is exposed through the Gateway, never directly. |
| serviceAccount.annotations | object | `{}` | Annotations, e.g. for EKS Pod Identity / IRSA in cloud environments. |
| serviceAccount.create | bool | `true` | Create a dedicated ServiceAccount. |
| serviceAccount.name | string | `""` | ServiceAccount name; generated from the release name when empty. |
| serviceMonitor.enabled | bool | `true` | Create a Prometheus Operator ServiceMonitor. |
| serviceMonitor.interval | string | `"30s"` | Scrape interval. |
| serviceMonitor.labels | object | `{}` | Extra labels on the ServiceMonitor. |
| terminationGracePeriodSeconds | int | `30` | Must exceed preStopSleepSeconds + config.shutdownTimeoutSeconds. |
| tolerations | list | `[]` | Tolerations. |
| topologySpread | list | `[{"maxSkew":1,"topologyKey":"kubernetes.io/hostname","whenUnsatisfiable":"ScheduleAnyway"}]` | Spread pods across these topology keys (one constraint each). `ScheduleAnyway` keeps pods schedulable while a node is drained; `Honor` ignores nodes the pods cannot run on. |
