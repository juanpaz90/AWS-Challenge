module "platform" {
  source = "../../../modules/platform-addons"

  chart_versions = var.chart_versions
  labels         = var.labels

  calico = {
    enabled             = true
    kubernetes_provider = "Kind"
    pod_subnet          = local.cluster.pod_subnet
  }

  gateway = {
    domain                  = var.domain
    service_type            = "NodePort"
    node_ports              = local.cluster.gateway_node_ports
    external_traffic_policy = "Cluster"
  }

  # kind kubelets use self-signed serving certificates (local only, never on EKS).
  metrics_server_kubelet_insecure_tls = true

  observability = {
    enabled = var.observability_enabled
  }

  local_registry_host = local.cluster.registry_host
}
