locals {
  monitoring_namespace = var.observability.enabled ? kubernetes_namespace_v1.this["monitoring"].metadata[0].name : null
  loki_url             = "http://loki.monitoring.svc.cluster.local:3100"
  grafana_host         = "grafana.${var.gateway.domain}"
  grafana_service      = "kube-prometheus-stack-grafana"
}

# --- 6a. kube-prometheus-stack: Prometheus, Alertmanager, Grafana ---------------------------
resource "helm_release" "kube_prometheus_stack" {
  count = var.observability.enabled ? 1 : 0

  name       = "kube-prometheus-stack"
  repository = "https://prometheus-community.github.io/helm-charts"
  chart      = "kube-prometheus-stack"
  version    = var.chart_versions.kube_prometheus_stack
  namespace  = local.monitoring_namespace
  timeout    = 900

  values = [yamlencode({
    # kind runs these control-plane components bound to localhost, so their targets would be
    # permanently down and their alerts permanently firing.
    kubeEtcd              = { enabled = false }
    kubeControllerManager = { enabled = false }
    kubeScheduler         = { enabled = false }
    kubeProxy             = { enabled = false }
    defaultRules = {
      rules = { etcd = false, kubeControllerManager = false, kubeSchedulerAlerting = false, kubeSchedulerRecording = false, kubeProxy = false }
    }

    prometheus = {
      prometheusSpec = {
        retention = var.observability.prometheus_retention
        # Select every ServiceMonitor/PodMonitor/PrometheusRule in the cluster, not only the
        # ones labelled for this Helm release (the Notes API chart ships its own).
        serviceMonitorSelectorNilUsesHelmValues = false
        podMonitorSelectorNilUsesHelmValues     = false
        ruleSelectorNilUsesHelmValues           = false
        probeSelectorNilUsesHelmValues          = false
        resources = {
          requests = { cpu = "100m", memory = "400Mi" }
          limits   = { memory = "1500Mi" }
        }
      }
    }

    alertmanager = {
      alertmanagerSpec = {
        resources = { requests = { cpu = "10m", memory = "32Mi" }, limits = { memory = "128Mi" } }
      }
    }

    grafana = {
      # The admin password is generated in-cluster by the chart (and reused on upgrade via
      # `lookup`), so it never appears in values or Terraform state (ADR-0007).
      adminUser = "admin"
      "grafana.ini" = {
        server = { root_url = "https://${local.grafana_host}" }
      }
      sidecar = {
        dashboards  = { searchNamespace = "ALL" } # dashboards as code from any namespace
        datasources = { defaultDatasourceEnabled = true }
      }
      additionalDataSources = [{
        name      = "Loki"
        type      = "loki"
        uid       = "loki"
        access    = "proxy"
        url       = local.loki_url
        isDefault = false
      }]
      resources = { requests = { cpu = "50m", memory = "128Mi" }, limits = { memory = "512Mi" } }
    }
  })]

  depends_on = [helm_release.calico]
}

# --- 6b. Loki (single binary, filesystem storage) --------------------------------------------
resource "helm_release" "loki" {
  count = var.observability.enabled ? 1 : 0

  name       = "loki"
  repository = "https://grafana.github.io/helm-charts"
  chart      = "loki"
  version    = var.chart_versions.loki
  namespace  = local.monitoring_namespace
  timeout    = 600

  values = [yamlencode({
    deploymentMode = "SingleBinary" # chart default is SimpleScalable
    loki = {
      auth_enabled  = false
      commonConfig  = { replication_factor = 1 }
      storage       = { type = "filesystem" }
      useTestSchema = false
      schemaConfig = {
        configs = [{
          from         = "2026-01-01"
          store        = "tsdb"
          object_store = "filesystem"
          schema       = "v13"
          index        = { prefix = "index_", period = "24h" }
        }]
      }
    }
    singleBinary = {
      replicas    = 1
      persistence = { size = var.observability.loki_storage_size }
      resources   = { requests = { cpu = "50m", memory = "256Mi" }, limits = { memory = "1Gi" } }
    }
    # Scalable targets, caches, gateway and test helpers are not used in single-binary mode.
    read         = { replicas = 0 }
    write        = { replicas = 0 }
    backend      = { replicas = 0 }
    chunksCache  = { enabled = false }
    resultsCache = { enabled = false }
    gateway      = { enabled = false }
    lokiCanary   = { enabled = false }
    test         = { enabled = false }
    minio        = { enabled = false }
  })]

  depends_on = [helm_release.calico]
}

# --- 6c. Grafana Alloy: ships pod logs to Loki through the Kubernetes API -------------------
resource "helm_release" "alloy" {
  count = var.observability.enabled ? 1 : 0

  name       = "alloy"
  repository = "https://grafana.github.io/helm-charts"
  chart      = "alloy"
  version    = var.chart_versions.alloy
  namespace  = local.monitoring_namespace
  timeout    = 600

  values = [yamlencode({
    # One replica tailing logs via the API server (loki.source.kubernetes) needs no hostPath
    # mounts. For larger clusters switch to a clustered DaemonSet.
    controller = { type = "deployment", replicas = 1 }
    alloy = {
      configMap = {
        content = <<-ALLOY
          discovery.kubernetes "pods" {
            role = "pod"
          }

          discovery.relabel "pods" {
            targets = discovery.kubernetes.pods.targets

            rule {
              source_labels = ["__meta_kubernetes_namespace"]
              target_label  = "namespace"
            }
            rule {
              source_labels = ["__meta_kubernetes_pod_name"]
              target_label  = "pod"
            }
            rule {
              source_labels = ["__meta_kubernetes_pod_container_name"]
              target_label  = "container"
            }
            rule {
              source_labels = ["__meta_kubernetes_pod_label_app_kubernetes_io_name"]
              target_label  = "app"
            }
          }

          loki.source.kubernetes "pods" {
            targets    = discovery.relabel.pods.output
            forward_to = [loki.write.default.receiver]
          }

          loki.write "default" {
            endpoint {
              url = "${local.loki_url}/loki/api/v1/push"
            }
          }
        ALLOY
      }
      resources = { requests = { cpu = "20m", memory = "64Mi" }, limits = { memory = "256Mi" } }
    }
  })]

  depends_on = [helm_release.loki]
}
