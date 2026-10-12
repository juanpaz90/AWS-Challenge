variable "chart_versions" {
  description = "Exact chart versions for every platform add-on."
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
}

variable "domain" {
  description = "Base domain served by the gateway; *.localtest.me resolves to 127.0.0.1."
  type        = string
}

variable "observability_enabled" {
  description = "Install Prometheus, Grafana, Loki and Alloy (set false on low-memory machines)."
  type        = bool
  default     = true
}

variable "labels" {
  description = "Labels added to platform namespaces."
  type        = map(string)
  default     = {}
}
