# Dashboards and alert/recording rules as code (Phase 10, ADR-0006). The source of truth is
# observability/: rule files stay plain Prometheus format so `promtool test rules` checks
# exactly what is deployed here.

resource "kubernetes_config_map_v1" "dashboard" {
  for_each = var.observability.enabled ? { for f in var.observability.dashboard_files : trimsuffix(basename(f), ".json") => f } : {}

  metadata {
    name      = "grafana-dashboard-${each.key}"
    namespace = kubernetes_namespace_v1.notes.metadata[0].name
    labels = {
      "grafana_dashboard"            = "1" # picked up by the Grafana sidecar (any namespace)
      "app.kubernetes.io/managed-by" = "terraform"
    }
  }

  data = {
    "${each.key}.json" = file(each.value)
  }
}

resource "kubernetes_manifest" "prometheus_rule" {
  for_each = var.observability.enabled ? { for f in var.observability.rule_files : trimsuffix(basename(f), ".rules.yaml") => f } : {}

  manifest = {
    apiVersion = "monitoring.coreos.com/v1"
    kind       = "PrometheusRule"
    metadata = {
      name      = each.key
      namespace = kubernetes_namespace_v1.notes.metadata[0].name
      labels = {
        "app.kubernetes.io/managed-by" = "terraform"
        "app.kubernetes.io/part-of"    = "notes"
      }
    }
    spec = {
      groups = yamldecode(file(each.value)).groups
    }
  }
}
