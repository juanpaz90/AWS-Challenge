output "gateway" {
  description = "Shared Gateway that application HTTPRoutes attach to (parentRefs)."
  value = {
    name                  = "platform"
    namespace             = kubernetes_namespace_v1.this["gateway"].metadata[0].name
    https_section         = "https"
    http_section          = "http"
    domain                = var.gateway.domain
    namespace_label_key   = local.gateway_access_label
    namespace_label_value = "true"
  }
}

output "cluster_issuer" {
  description = "cert-manager ClusterIssuer backed by the local CA."
  value       = "local-ca"
}

output "grafana_url" {
  description = "Grafana URL through the gateway (null when observability is disabled)."
  value       = var.observability.enabled ? "https://${local.grafana_host}" : null
}

output "namespaces" {
  description = "Namespaces created by this module and their Pod Security enforce level."
  value       = merge({ for k, v in local.namespaces : k => v.enforce }, var.calico.enabled ? { "tigera-operator" = "privileged" } : {})
}
