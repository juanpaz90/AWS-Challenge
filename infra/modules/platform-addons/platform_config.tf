locals {
  platform_config_chart = "${path.module}/charts/platform-config"
  # The helm provider only notices a local chart change when the chart version or values
  # change, so the content hash of the chart is passed as a value to force an upgrade.
  platform_config_checksum = sha1(join("", [
    for f in sort(fileset(local.platform_config_chart, "**")) : filesha1("${local.platform_config_chart}/${f}")
  ]))
}

# --- 7. Platform custom resources ------------------------------------------------------------
# Issuers, the shared Gateway and the Grafana route are custom resources whose CRDs are
# installed by the releases above. They live in a local chart instead of kubernetes_manifest,
# which would fail at plan time on a fresh cluster because the CRDs do not exist yet.
resource "helm_release" "platform_config" {
  name      = "platform-config"
  chart     = local.platform_config_chart
  namespace = kubernetes_namespace_v1.this["gateway"].metadata[0].name
  timeout   = 600

  values = [yamlencode({
    checksum = local.platform_config_checksum
    domain   = var.gateway.domain

    certManager = {
      namespace = kubernetes_namespace_v1.this["cert-manager"].metadata[0].name
    }

    gateway = {
      name                  = "platform"
      gatewayClassName      = "envoy"
      serviceType           = var.gateway.service_type
      externalTrafficPolicy = var.gateway.external_traffic_policy
      nodePorts             = var.gateway.node_ports
      accessLabel           = local.gateway_access_label
    }

    grafana = {
      enabled     = var.observability.enabled
      namespace   = local.monitoring_namespace
      host        = local.grafana_host
      serviceName = local.grafana_service
    }

    localRegistry = {
      host = var.local_registry_host
    }
  })]

  depends_on = [
    helm_release.cert_manager,
    helm_release.envoy_gateway,
    helm_release.kube_prometheus_stack,
  ]
}
