output "gateway" {
  description = "Shared Gateway reference for application HTTPRoutes."
  value       = module.platform.gateway
}

output "cluster_issuer" {
  description = "ClusterIssuer for application certificates."
  value       = module.platform.cluster_issuer
}

output "grafana_url" {
  description = "Grafana through the gateway."
  value       = module.platform.grafana_url
}

output "namespaces" {
  description = "Platform namespaces and their Pod Security enforce level."
  value       = module.platform.namespaces
}

output "context_name" {
  description = "kubectl context of the cluster this stack targets."
  value       = local.cluster.context_name
}
