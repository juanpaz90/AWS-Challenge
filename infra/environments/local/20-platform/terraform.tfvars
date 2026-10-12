# Local platform. Versions verified on 2026-10-11 (Artifact Hub / chart repos; none deprecated).
chart_versions = {
  calico                = "v3.33.0" # tigera-operator and crd.projectcalico.org.v1 charts
  cert_manager          = "v1.21.2"
  envoy_gateway         = "1.9.2"
  metrics_server        = "3.14.0"
  cloudnative_pg        = "0.29.1"
  kube_prometheus_stack = "92.3.0"
  loki                  = "7.3.0"
  alloy                 = "1.13.1"
}

domain                = "localtest.me"
observability_enabled = true

labels = {
  project     = "aws-challenge"
  environment = "local"
}
