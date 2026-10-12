output "cluster_name" {
  description = "Name of the kind cluster."
  value       = module.kind_cluster.cluster_name
}

output "context_name" {
  description = "kubectl context name (kubectl --context <value>)."
  value       = module.kind_cluster.context_name
}

output "kubernetes_version" {
  description = "Kubernetes version of the nodes."
  value       = module.kind_cluster.kubernetes_version
}

output "kubeconfig_path" {
  description = "Kubeconfig file containing the context."
  value       = module.kind_cluster.kubeconfig_path
}

output "endpoint" {
  description = "API server endpoint."
  value       = module.kind_cluster.endpoint
}

output "cluster_ca_certificate" {
  description = "API server CA certificate."
  value       = module.kind_cluster.cluster_ca_certificate
  sensitive   = true
}

output "client_certificate" {
  description = "Client certificate for the helm/kubernetes providers."
  value       = module.kind_cluster.client_certificate
  sensitive   = true
}

output "client_key" {
  description = "Client key for the helm/kubernetes providers."
  value       = module.kind_cluster.client_key
  sensitive   = true
}

output "pod_subnet" {
  description = "Pod CIDR, consumed by the Calico install in 20-platform."
  value       = var.pod_subnet
}

output "gateway_node_ports" {
  description = "NodePorts the gateway must expose so the host port mappings reach it."
  value       = { for k, m in var.port_mappings : k => m.container_port }
}

output "registry_host" {
  description = "Registry address for pushes and image references."
  value       = module.kind_cluster.registry_host
}
