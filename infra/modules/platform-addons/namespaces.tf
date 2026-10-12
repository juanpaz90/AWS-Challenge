locals {
  # Label that lets a namespace attach HTTPRoutes to the shared Gateway (allowedRoutes selector).
  gateway_access_label = "platform.notes/gateway-access"

  # Pod Security Admission per namespace: `enforce` is the lowest level the component needs;
  # `warn`/`audit` stay at restricted so any gap is visible. Exceptions are documented in
  # docs/architecture.md §3.3.
  namespaces = merge(
    var.calico.enabled ? {
      # Exception: the operator deploys calico-node with host networking and privileges.
      "tigera-operator" = { enforce = "privileged", gateway_access = false }
    } : {},
    {
      "cert-manager" = { enforce = "restricted", gateway_access = false }
      "gateway"      = { enforce = "restricted", gateway_access = false }
      "cnpg-system"  = { enforce = "restricted", gateway_access = false }
    },
    var.observability.enabled ? {
      # Exception: node-exporter needs hostNetwork/hostPID/hostPath.
      "monitoring" = { enforce = "privileged", gateway_access = true }
    } : {},
  )
}

resource "kubernetes_namespace_v1" "this" {
  for_each = local.namespaces

  metadata {
    name = each.key
    labels = merge(
      var.labels,
      {
        "app.kubernetes.io/managed-by"               = "terraform"
        "pod-security.kubernetes.io/enforce"         = each.value.enforce
        "pod-security.kubernetes.io/enforce-version" = "latest"
        "pod-security.kubernetes.io/warn"            = "restricted"
        "pod-security.kubernetes.io/audit"           = "restricted"
      },
      each.value.gateway_access ? { (local.gateway_access_label) = "true" } : {},
    )
  }
}
