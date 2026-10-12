# Module: platform-addons

Installs the platform layer from official Helm charts, in a fixed order (each step `depends_on` the previous one):

| # | Release | Chart | Namespace | Purpose |
|---|---|---|---|---|
| 1 | Calico CRDs (`kubernetes_manifest`), `calico` | `crd.projectcalico.org.v1` (rendered), `tigera-operator` | `tigera-operator` (+ `calico-system`) | CNI with NetworkPolicy enforcement ([ADR-0005](../../../docs/adr/0005-calico-on-kind.md)) |
| 2 | `cert-manager` | `cert-manager` | `cert-manager` | Certificates |
| 3 | `envoy-gateway` | `gateway-helm` (OCI) | `gateway` | Gateway API implementation ([ADR-0003](../../../docs/adr/0003-envoy-gateway-over-ingress-nginx.md)) |
| 4 | `metrics-server` | `metrics-server` | `kube-system` | Resource metrics for the HPA |
| 5 | `cnpg` | `cloudnative-pg` | `cnpg-system` | PostgreSQL operator ([ADR-0004](../../../docs/adr/0004-cloudnativepg-vs-rds.md)) |
| 6 | `kube-prometheus-stack`, `loki`, `alloy` | — | `monitoring` | Metrics, alerts, Grafana, logs ([ADR-0006](../../../docs/adr/0006-observability-stack.md)) |
| 7 | `platform-config` | local chart `charts/platform-config` | `gateway` | Custom resources that need the CRDs above |

## Why a local chart for the custom resources

ClusterIssuers, the CA and wildcard certificates, the `EnvoyProxy`, `GatewayClass`, `Gateway` and Grafana's `HTTPRoute` are custom resources whose CRDs are installed by the releases above. `kubernetes_manifest` validates against the live API at **plan** time, so on a fresh cluster it fails before the CRDs exist. A Helm release only talks to the API at apply time, after its `depends_on` releases, so the whole platform installs in one `terraform apply`. The chart's content hash is passed as a value so template edits always trigger an upgrade.

## Notable choices

- **Calico CRDs applied by Terraform.** Since v3.33 the `tigera-operator` chart no longer ships CRDs. The CRD chart is too large to be a Helm release (the release Secret would exceed 1 MiB), so it is rendered with `helm_template` and each CRD is applied with `kubernetes_manifest`; `manageCRDs=false` keeps Terraform the single owner.
- **Gateway exposure.** On kind the Envoy Service is a `NodePort` pinned (via `EnvoyProxy` patch) to the ports kind maps to the host, with `externalTrafficPolicy: Cluster` so the control-plane node forwards traffic even though no Envoy pod runs on it.
- **TLS.** self-signed `ClusterIssuer` → `local-ca` CA certificate → `local-ca` `ClusterIssuer` → wildcard `*.<domain>` certificate on the Gateway. HTTP redirects to HTTPS.
- **Route admission.** The HTTPS listener only accepts `HTTPRoute`s from namespaces labelled `platform.notes/gateway-access=true`.
- **Pod Security.** `restricted` is enforced everywhere except `tigera-operator` and `monitoring` (host access for calico-node and node-exporter); `warn`/`audit` are `restricted` on all of them.
- **No secrets in values.** Grafana's admin password is generated in-cluster by the chart and reused on upgrade.
- **kind-specific settings are inputs**, not hardcoded: `calico.enabled`, `gateway.service_type`, `metrics_server_kubelet_insecure_tls`, `local_registry_host`.

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

## Resources

| Name | Type |
| ---- | ---- |
| [helm_release.alloy](https://registry.terraform.io/providers/hashicorp/helm/latest/docs/resources/release) | resource |
| [helm_release.calico](https://registry.terraform.io/providers/hashicorp/helm/latest/docs/resources/release) | resource |
| [helm_release.cert_manager](https://registry.terraform.io/providers/hashicorp/helm/latest/docs/resources/release) | resource |
| [helm_release.cloudnative_pg](https://registry.terraform.io/providers/hashicorp/helm/latest/docs/resources/release) | resource |
| [helm_release.envoy_gateway](https://registry.terraform.io/providers/hashicorp/helm/latest/docs/resources/release) | resource |
| [helm_release.kube_prometheus_stack](https://registry.terraform.io/providers/hashicorp/helm/latest/docs/resources/release) | resource |
| [helm_release.loki](https://registry.terraform.io/providers/hashicorp/helm/latest/docs/resources/release) | resource |
| [helm_release.metrics_server](https://registry.terraform.io/providers/hashicorp/helm/latest/docs/resources/release) | resource |
| [helm_release.platform_config](https://registry.terraform.io/providers/hashicorp/helm/latest/docs/resources/release) | resource |
| [kubernetes_manifest.calico_crds](https://registry.terraform.io/providers/hashicorp/kubernetes/latest/docs/resources/manifest) | resource |
| [kubernetes_namespace_v1.this](https://registry.terraform.io/providers/hashicorp/kubernetes/latest/docs/resources/namespace_v1) | resource |
| [helm_template.calico_crds](https://registry.terraform.io/providers/hashicorp/helm/latest/docs/data-sources/template) | data source |

## Inputs

| Name | Description | Type | Default | Required |
| ---- | ----------- | ---- | ------- | :------: |
| calico | Calico CNI via the Tigera operator (ADR-0005). Disable where the platform provides a NetworkPolicy-capable CNI (EKS VPC CNI). | <pre>object({<br/>    enabled             = bool<br/>    kubernetes_provider = optional(string, "Kind")<br/>    pod_subnet          = optional(string, "10.244.0.0/16")<br/>  })</pre> | n/a | yes |
| chart\_versions | Exact chart versions. Verify status (active/deprecated/retired) before bumping. | <pre>object({<br/>    calico                = string<br/>    cert_manager          = string<br/>    envoy_gateway         = string<br/>    metrics_server        = string<br/>    cloudnative_pg        = string<br/>    kube_prometheus_stack = string<br/>    loki                  = string<br/>    alloy                 = string<br/>  })</pre> | n/a | yes |
| gateway | Shared Envoy Gateway (ADR-0003). On kind the proxy Service is a NodePort matching the cluster's host port mappings. | <pre>object({<br/>    domain                  = string<br/>    service_type            = optional(string, "NodePort")<br/>    node_ports              = optional(map(number), {})<br/>    external_traffic_policy = optional(string, "Cluster")<br/>  })</pre> | n/a | yes |
| observability | kube-prometheus-stack, Loki (single binary) and Alloy (ADR-0006). | <pre>object({<br/>    enabled              = bool<br/>    prometheus_retention = optional(string, "24h")<br/>    loki_storage_size    = optional(string, "5Gi")<br/>  })</pre> | n/a | yes |
| labels | Labels added to namespaces created by this module. | `map(string)` | `{}` | no |
| local\_registry\_host | Publishes kind's local-registry-hosting ConfigMap (KEP-1755) for this host, e.g. localhost:5001. null on clusters without a local registry. | `string` | `null` | no |
| metrics\_server\_kubelet\_insecure\_tls | kind-only: kubelets serve self-signed certificates, so metrics-server must skip verification. Never enable on EKS. | `bool` | `false` | no |

## Outputs

| Name | Description |
| ---- | ----------- |
| cluster\_issuer | cert-manager ClusterIssuer backed by the local CA. |
| gateway | Shared Gateway that application HTTPRoutes attach to (parentRefs). |
| grafana\_url | Grafana URL through the gateway (null when observability is disabled). |
| namespaces | Namespaces created by this module and their Pod Security enforce level. |
<!-- END_TF_DOCS -->
