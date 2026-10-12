# Platform add-ons, installed in this order (each release depends on the previous step):
#   1. Calico CRDs, then the Tigera operator → nodes become Ready
#   2. cert-manager      → CRDs + controller
#   3. Envoy Gateway     → Gateway API + Envoy Gateway CRDs + controller
#   4. metrics-server    → resource metrics for HPA
#   5. CloudNativePG     → database operator + CRDs
#   6. observability     → kube-prometheus-stack, Loki, Alloy
#   7. platform-config   → custom resources that need the CRDs above (local chart)

# --- 1. Calico ------------------------------------------------------------------------------
# Since v3.33 the tigera-operator chart ships no CRDs, so the Installation resource it renders
# cannot be applied in the same release; the CRDs come from a separate chart applied first.
#   - crd.projectcalico.org.v1 (classic CRDs) rather than projectcalico.org.v3: the v3 chart
#     always renders MutatingAdmissionPolicies, an API kind 1.35 does not serve by default.
#   - Rendered with helm_template and applied per CRD, not as a helm_release: the rendered
#     chart exceeds the 1 MiB limit of the Secret Helm stores each release in. This is the
#     declarative form of Calico's documented `helm template | kubectl apply --server-side`.
data "helm_template" "calico_crds" {
  count = var.calico.enabled ? 1 : 0

  name       = "calico-crds"
  repository = "https://docs.tigera.io/calico/charts"
  chart      = "crd.projectcalico.org.v1"
  version    = var.chart_versions.calico
  namespace  = "tigera-operator"
}

locals {
  calico_crd_documents = var.calico.enabled ? flatten([
    for content in values(data.helm_template.calico_crds[0].manifests) : split("\n---\n", content)
  ]) : []

  calico_crds = {
    for doc in local.calico_crd_documents :
    yamldecode(doc).metadata.name => { for k, v in yamldecode(doc) : k => v if k != "status" }
    if try(yamldecode(doc).kind, null) == "CustomResourceDefinition"
  }
}

resource "kubernetes_manifest" "calico_crds" {
  for_each = local.calico_crds

  manifest = each.value
}

resource "helm_release" "calico" {
  count = var.calico.enabled ? 1 : 0

  name       = "calico"
  repository = "https://docs.tigera.io/calico/charts"
  chart      = "tigera-operator"
  version    = var.chart_versions.calico
  namespace  = kubernetes_namespace_v1.this["tigera-operator"].metadata[0].name
  timeout    = 600

  values = [yamlencode({
    # CRDs are owned by Terraform (kubernetes_manifest.calico_crds); the operator must not manage them too.
    manageCRDs = false
    installation = {
      kubernetesProvider = var.calico.kubernetes_provider
      calicoNetwork = {
        bgp = "Disabled"
        ipPools = [{
          cidr          = var.calico.pod_subnet
          encapsulation = "VXLAN"
          natOutgoing   = "Enabled"
          nodeSelector  = "all()"
        }]
      }
    }
    # Optional Calico components not needed here; they only cost memory.
    apiServer = { enabled = false }
    goldmane  = { enabled = false }
    whisker   = { enabled = false }
  })]

  depends_on = [kubernetes_manifest.calico_crds]
}

# --- 2. cert-manager ------------------------------------------------------------------------
resource "helm_release" "cert_manager" {
  name       = "cert-manager"
  repository = "https://charts.jetstack.io"
  chart      = "cert-manager"
  version    = var.chart_versions.cert_manager
  namespace  = kubernetes_namespace_v1.this["cert-manager"].metadata[0].name
  timeout    = 600

  values = [yamlencode({
    # CRDs are removed on uninstall so `destroy` leaves nothing behind (local, throwaway).
    crds = { enabled = true, keep = false }
  })]

  depends_on = [helm_release.calico]
}

# --- 3. Envoy Gateway -----------------------------------------------------------------------
resource "helm_release" "envoy_gateway" {
  name       = "envoy-gateway"
  repository = "oci://docker.io/envoyproxy"
  chart      = "gateway-helm"
  version    = var.chart_versions.envoy_gateway
  namespace  = kubernetes_namespace_v1.this["gateway"].metadata[0].name
  timeout    = 600

  # Chart defaults install the Gateway API CRDs and Envoy Gateway CRDs (as a subchart, so
  # upgrades update them too).

  depends_on = [helm_release.calico]
}

# --- 4. metrics-server ----------------------------------------------------------------------
resource "helm_release" "metrics_server" {
  name       = "metrics-server"
  repository = "https://kubernetes-sigs.github.io/metrics-server/"
  chart      = "metrics-server"
  version    = var.chart_versions.metrics_server
  namespace  = "kube-system"
  timeout    = 600

  values = [yamlencode({
    args = var.metrics_server_kubelet_insecure_tls ? ["--kubelet-insecure-tls"] : []
  })]

  depends_on = [helm_release.calico]
}

# --- 5. CloudNativePG -----------------------------------------------------------------------
resource "helm_release" "cloudnative_pg" {
  name       = "cnpg"
  repository = "https://cloudnative-pg.github.io/charts"
  chart      = "cloudnative-pg"
  version    = var.chart_versions.cloudnative_pg
  namespace  = kubernetes_namespace_v1.this["cnpg-system"].metadata[0].name
  timeout    = 600

  depends_on = [helm_release.calico]
}
