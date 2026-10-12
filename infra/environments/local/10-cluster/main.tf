module "kind_cluster" {
  source = "../../../modules/kind-cluster"

  cluster_name    = var.cluster_name
  node_image      = var.node_image
  worker_count    = var.worker_count
  port_mappings   = var.port_mappings
  pod_subnet      = var.pod_subnet
  network_name    = "kind"
  labels          = var.labels
  generated_dir   = abspath("${path.module}/.generated")
  kubeconfig_path = pathexpand(var.kubeconfig_path)

  registry = {
    image     = var.registry_image
    host_port = var.registry_host_port
  }
}
