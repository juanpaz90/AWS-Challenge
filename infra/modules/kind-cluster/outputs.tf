output "cluster_name" {
  description = "Name of the kind cluster."
  value       = kind_cluster.this.name
}

output "context_name" {
  description = "kubectl context name for the cluster."
  value       = local.context_name
}

output "kubernetes_version" {
  description = "Kubernetes version of the nodes (from the pinned node image)."
  value       = local.kubernetes_version
}

output "kubeconfig_path" {
  description = "Kubeconfig file the context was merged into."
  value       = kind_cluster.this.kubeconfig_path
}

output "endpoint" {
  description = "Kubernetes API server endpoint, for the helm/kubernetes providers in 20-platform and 30-apps."
  value       = kind_cluster.this.endpoint
}

output "cluster_ca_certificate" {
  description = "PEM CA certificate of the API server."
  value       = kind_cluster.this.cluster_ca_certificate
  sensitive   = true
}

output "client_certificate" {
  description = "PEM client certificate (cluster-admin) for the local cluster."
  value       = kind_cluster.this.client_certificate
  sensitive   = true
}

output "client_key" {
  description = "PEM client key (cluster-admin) for the local cluster. Local state only; never used outside kind."
  value       = kind_cluster.this.client_key
  sensitive   = true
}

output "network_name" {
  description = "Docker network shared by the nodes and the registry."
  value       = docker_network.kind.name
}

output "registry_host" {
  description = "Registry address used by the host and in image references (e.g. localhost:5001/notes-api:<sha>)."
  value       = local.registry_host
}

output "registry_in_cluster" {
  description = "Registry address as seen from inside the kind network."
  value       = local.registry_in_cluster
}
