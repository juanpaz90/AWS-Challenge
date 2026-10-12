variable "chart_versions" {
  description = "Exact chart versions. Verify status (active/deprecated/retired) before bumping."
  type = object({
    calico                = string
    cert_manager          = string
    envoy_gateway         = string
    metrics_server        = string
    cloudnative_pg        = string
    kube_prometheus_stack = string
    loki                  = string
    alloy                 = string
  })

  validation {
    condition     = alltrue([for v in values(var.chart_versions) : can(regex("^v?[0-9]+\\.[0-9]+\\.[0-9]+$", v))])
    error_message = "Every chart version must be an exact X.Y.Z (optionally v-prefixed); ranges and 'latest' are not allowed."
  }
}

variable "calico" {
  description = "Calico CNI via the Tigera operator (ADR-0005). Disable where the platform provides a NetworkPolicy-capable CNI (EKS VPC CNI)."
  type = object({
    enabled             = bool
    kubernetes_provider = optional(string, "Kind")
    pod_subnet          = optional(string, "10.244.0.0/16")
  })

  validation {
    condition     = can(cidrnetmask(var.calico.pod_subnet))
    error_message = "calico.pod_subnet must be a valid IPv4 CIDR."
  }
}

variable "gateway" {
  description = "Shared Envoy Gateway (ADR-0003). On kind the proxy Service is a NodePort matching the cluster's host port mappings."
  type = object({
    domain                  = string
    service_type            = optional(string, "NodePort")
    node_ports              = optional(map(number), {})
    external_traffic_policy = optional(string, "Cluster")
    replicas                = optional(number, 2)
  })

  validation {
    condition     = var.gateway.replicas >= 1 && floor(var.gateway.replicas) == var.gateway.replicas
    error_message = "gateway.replicas must be a whole number >= 1 (use >= 2 so node drains keep the gateway up)."
  }

  validation {
    condition     = contains(["NodePort", "LoadBalancer", "ClusterIP"], var.gateway.service_type)
    error_message = "gateway.service_type must be NodePort, LoadBalancer or ClusterIP."
  }

  validation {
    condition     = var.gateway.service_type != "NodePort" || (contains(keys(var.gateway.node_ports), "http") && contains(keys(var.gateway.node_ports), "https"))
    error_message = "A NodePort gateway needs node_ports.http and node_ports.https (the ports kind maps to the host)."
  }

  validation {
    condition     = alltrue([for p in values(var.gateway.node_ports) : p >= 30000 && p <= 32767])
    error_message = "node_ports must be in the Kubernetes NodePort range 30000-32767."
  }

  validation {
    condition     = contains(["Cluster", "Local"], var.gateway.external_traffic_policy)
    error_message = "gateway.external_traffic_policy must be Cluster or Local."
  }
}

variable "metrics_server_kubelet_insecure_tls" {
  description = "kind-only: kubelets serve self-signed certificates, so metrics-server must skip verification. Never enable on EKS."
  type        = bool
  default     = false
}

variable "observability" {
  description = "kube-prometheus-stack, Loki (single binary) and Alloy (ADR-0006)."
  type = object({
    enabled              = bool
    prometheus_retention = optional(string, "24h")
    loki_storage_size    = optional(string, "5Gi")
  })
}

variable "local_registry_host" {
  description = "Publishes kind's local-registry-hosting ConfigMap (KEP-1755) for this host, e.g. localhost:5001. null on clusters without a local registry."
  type        = string
  default     = null
}

variable "labels" {
  description = "Labels added to namespaces created by this module."
  type        = map(string)
  default     = {}
}
