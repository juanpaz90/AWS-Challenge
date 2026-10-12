locals {
  # Label that lets a namespace attach HTTPRoutes to the shared Gateway (allowedRoutes selector).
  gateway_access_label = "platform.notes/gateway-access"

  # Pod Security Admission per namespace: `enforce` is the lowest level the component needs;
  # `warn`/`audit` stay at restricted so any gap is visible. Exceptions are documented in
  # docs/architecture.md §3.3.
  namespaces = merge(
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

  namespace_labels = merge(var.labels, {
    "app.kubernetes.io/managed-by"               = "terraform"
    "pod-security.kubernetes.io/enforce-version" = "latest"
    "pod-security.kubernetes.io/warn"            = "restricted"
    "pod-security.kubernetes.io/audit"           = "restricted"
  })
}

# Calico's own namespace. Exception: the operator deploys calico-node with host networking
# and privileges.
resource "kubernetes_namespace_v1" "tigera_operator" {
  count = var.calico.enabled ? 1 : 0

  metadata {
    name   = "tigera-operator"
    labels = merge(local.namespace_labels, { "pod-security.kubernetes.io/enforce" = "privileged" })
  }
}

moved {
  from = kubernetes_namespace_v1.this["tigera-operator"]
  to   = kubernetes_namespace_v1.tigera_operator[0]
}

resource "kubernetes_namespace_v1" "this" {
  for_each = local.namespaces

  metadata {
    name = each.key
    labels = merge(
      local.namespace_labels,
      { "pod-security.kubernetes.io/enforce" = each.value.enforce },
      each.value.gateway_access ? { (local.gateway_access_label) = "true" } : {},
    )
  }

  # Destroy order: every namespace, and therefore every pod in it, must be gone before Calico
  # is uninstalled. Otherwise the kubelet cannot tear down pod networking ("plugin
  # type=calico failed (delete) ... Unauthorized") and pods hang in Terminating forever.
  depends_on = [helm_release.calico]
}
