# Module: notes-app

Deploys the application layer into one namespace: the PostgreSQL database (CloudNativePG, [ADR-0004](../../../docs/adr/0004-cloudnativepg-vs-rds.md)), the network policies that protect it, and the Notes API Helm release ([`charts/notes-api`](../../../charts/notes-api)).

| Order | Resource | Notes |
|---|---|---|
| 1 | `kubernetes_namespace_v1` | Pod Security `restricted` (enforce, warn, audit); labelled so it may attach routes to the shared Gateway |
| 2 | `kubernetes_network_policy_v1` ×2 | Everything that selects the **database** pods: ingress from the API release (5432), the CNPG operator (8000, 5432), other instances (5432, 8000) and Prometheus (9187); egress to the Kubernetes API server, other instances and DNS |
| 3 | `helm_release.database` | Official CNPG `cluster` chart: pinned PostgreSQL image, operator-generated `<name>-app` Secret, no superuser Secret, PDB only with more than one instance, PodMonitor + PrometheusRule |
| 4 | `terraform_data.database_ready` | `kubectl wait --for=condition=Ready` on the CNPG `Cluster` |
| 5 | `helm_release.api` | The Notes API chart with the environment values files plus the image (tag and digest) |

## Why these choices

- **Database policies live here, not in the chart.** The chart's migration Job is a `pre-install` hook and runs before any chart resource exists, so the rule letting it reach PostgreSQL must already be in place.
- **API server egress from discovered endpoints.** The CNPG instance manager calls the Kubernetes API; NetworkPolicies are evaluated after the Service DNAT, so the allowed destination is the API server's EndpointSlice addresses and ports (read with `kubernetes_resources`), not the `kubernetes` Service IP.
- **Readiness gate.** Helm does not wait for custom resources: the `cluster` release completes as soon as the `Cluster` object exists, long before PostgreSQL accepts connections. Without the gate the API's migration hook would race the database bootstrap. It is a read-only wait and re-runs whenever the database release changes.
- **Deploy by digest.** When `api.image.digest` is set the chart pins `repository@digest`, so a rebuilt tag can never be served stale from a node's image cache.
- **Local chart upgrades.** The chart content hash is written into the release description, because the helm provider only upgrades a local chart when its version or values change.

<!-- BEGIN_TF_DOCS -->
## Requirements

| Name | Version |
| ---- | ------- |
| terraform | >= 1.10.0 |
| helm | >= 3.3.0 |
| kubernetes | >= 3.3.0 |

## Providers

| Name | Version |
| ---- | ------- |
| helm | 3.3.0 |
| kubernetes | 3.3.0 |
| terraform | n/a |

## Resources

| Name | Type |
| ---- | ---- |
| [helm_release.api](https://registry.terraform.io/providers/hashicorp/helm/latest/docs/resources/release) | resource |
| [helm_release.database](https://registry.terraform.io/providers/hashicorp/helm/latest/docs/resources/release) | resource |
| [kubernetes_config_map_v1.dashboard](https://registry.terraform.io/providers/hashicorp/kubernetes/latest/docs/resources/config_map_v1) | resource |
| [kubernetes_manifest.prometheus_rule](https://registry.terraform.io/providers/hashicorp/kubernetes/latest/docs/resources/manifest) | resource |
| [kubernetes_namespace_v1.notes](https://registry.terraform.io/providers/hashicorp/kubernetes/latest/docs/resources/namespace_v1) | resource |
| [kubernetes_network_policy_v1.database_egress](https://registry.terraform.io/providers/hashicorp/kubernetes/latest/docs/resources/network_policy_v1) | resource |
| [kubernetes_network_policy_v1.database_ingress](https://registry.terraform.io/providers/hashicorp/kubernetes/latest/docs/resources/network_policy_v1) | resource |
| [terraform_data.database_ready](https://registry.terraform.io/providers/hashicorp/terraform/latest/docs/resources/data) | resource |
| [kubernetes_resources.api_server](https://registry.terraform.io/providers/hashicorp/kubernetes/latest/docs/data-sources/resources) | data source |

## Inputs

| Name | Description | Type | Default | Required |
| ---- | ----------- | ---- | ------- | :------: |
| api | Notes API Helm release (charts/notes-api). | <pre>object({<br/>    chart_path   = string<br/>    values_files = list(string)<br/>    image = object({<br/>      repository = string<br/>      tag        = string<br/>      digest     = optional(string, "")<br/>    })<br/>    app_message = optional(string)<br/>  })</pre> | n/a | yes |
| database | CloudNativePG cluster, deployed with the official `cluster` chart. | <pre>object({<br/>    name          = optional(string, "notes-db")<br/>    chart_version = string<br/>    image         = string<br/>    instances     = optional(number, 1)<br/>    storage_size  = optional(string, "2Gi")<br/>    storage_class = optional(string, "")<br/>    database      = optional(string, "app")<br/>    owner         = optional(string, "app")<br/>    monitoring    = optional(bool, true)<br/>  })</pre> | n/a | yes |
| gateway\_access\_label | Label (key) that lets a namespace attach routes to the shared Gateway (from 20-platform). | `string` | n/a | yes |
| kube\_context | kubectl context used only to wait for the database to become Ready (Helm does not wait for custom resources). | `string` | n/a | yes |
| labels | Labels added to the namespace. | `map(string)` | `{}` | no |
| namespace | Namespace for the API and its database (Pod Security restricted). | `string` | `"notes"` | no |
| network\_policy | Peers allowed to reach the database pods, and the Kubernetes API endpoints they may call. | <pre>object({<br/>    operator_namespace = optional(string, "cnpg-system")<br/>    operator_pod_labels = optional(map(string), {<br/>      "app.kubernetes.io/name" = "cloudnative-pg"<br/>    })<br/>    monitoring_namespace = optional(string, "monitoring")<br/>    monitoring_pod_labels = optional(map(string), {<br/>      "app.kubernetes.io/name" = "prometheus"<br/>    })<br/>    dns_namespace  = optional(string, "kube-system")<br/>    dns_pod_labels = optional(map(string), { "k8s-app" = "kube-dns" })<br/>  })</pre> | `{}` | no |
| observability | Dashboards (Grafana JSON) and Prometheus rule files (plain, promtool-tested) to deploy, as absolute paths. The PrometheusRule CRD is installed by 20-platform. | <pre>object({<br/>    enabled         = optional(bool, true)<br/>    dashboard_files = optional(list(string), [])<br/>    rule_files      = optional(list(string), [])<br/>  })</pre> | `{}` | no |

## Outputs

| Name | Description |
| ---- | ----------- |
| api\_release | Helm release name and revision of the Notes API. |
| database | Database cluster name, credentials Secret (generated by CNPG) and read-write Service. |
| namespace | Namespace of the API and database. |
<!-- END_TF_DOCS -->
