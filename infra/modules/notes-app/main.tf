locals {
  db_selector = { "cnpg.io/cluster" = var.database.name }
  api_release = "notes-api"
  # Labels on every pod of the notes-api release (API and migration Job).
  api_pod_labels = {
    "app.kubernetes.io/name"     = "notes-api"
    "app.kubernetes.io/instance" = local.api_release
  }

  # The helm provider only upgrades a local chart when its version or values change, so the
  # chart content hash goes into the release description to trigger upgrades on edits.
  api_chart_checksum = sha1(join("", [
    for f in sort(fileset(var.api.chart_path, "**")) : filesha1("${var.api.chart_path}/${f}")
  ]))
}

# --- Namespace ------------------------------------------------------------------------------
resource "kubernetes_namespace_v1" "notes" {
  metadata {
    name = var.namespace
    labels = merge(var.labels, {
      "app.kubernetes.io/managed-by"               = "terraform"
      "pod-security.kubernetes.io/enforce"         = "restricted"
      "pod-security.kubernetes.io/enforce-version" = "latest"
      "pod-security.kubernetes.io/warn"            = "restricted"
      "pod-security.kubernetes.io/audit"           = "restricted"
      (var.gateway_access_label)                   = "true"
    })
  }
}

# --- Database network policies --------------------------------------------------------------
# Everything that selects the database pods lives here, next to the database, so it exists
# before the notes-api chart's pre-install migration hook runs (see charts/notes-api/README).

# The CNPG instance manager talks to the Kubernetes API; with default-deny egress that needs
# an explicit allow to the API server endpoints (policies apply after the Service DNAT).
data "kubernetes_resources" "api_server" {
  api_version    = "discovery.k8s.io/v1"
  kind           = "EndpointSlice"
  namespace      = "default"
  label_selector = "kubernetes.io/service-name=kubernetes"
}

locals {
  api_server_ips   = distinct(flatten([for s in data.kubernetes_resources.api_server.objects : [for e in s.endpoints : e.addresses]]))
  api_server_ports = distinct(flatten([for s in data.kubernetes_resources.api_server.objects : [for p in s.ports : p.port]]))
}

resource "kubernetes_network_policy_v1" "database_ingress" {
  metadata {
    name      = "${var.database.name}-ingress"
    namespace = kubernetes_namespace_v1.notes.metadata[0].name
  }

  spec {
    pod_selector {
      match_labels = local.db_selector
    }
    policy_types = ["Ingress"]

    # Notes API pods and its migration Job → PostgreSQL. Nothing else in the cluster.
    ingress {
      from {
        pod_selector {
          match_labels = local.api_pod_labels
        }
      }
      ports {
        port     = "5432"
        protocol = "TCP"
      }
    }

    # CNPG operator → instance manager (status) and PostgreSQL.
    ingress {
      from {
        namespace_selector {
          match_labels = { "kubernetes.io/metadata.name" = var.network_policy.operator_namespace }
        }
        pod_selector {
          match_labels = var.network_policy.operator_pod_labels
        }
      }
      ports {
        port     = "8000"
        protocol = "TCP"
      }
      ports {
        port     = "5432"
        protocol = "TCP"
      }
    }

    # Instances of the same cluster → each other (replication, status), needed with >1 instance.
    ingress {
      from {
        pod_selector {
          match_labels = local.db_selector
        }
      }
      ports {
        port     = "5432"
        protocol = "TCP"
      }
      ports {
        port     = "8000"
        protocol = "TCP"
      }
    }

    # Prometheus → PostgreSQL exporter.
    ingress {
      from {
        namespace_selector {
          match_labels = { "kubernetes.io/metadata.name" = var.network_policy.monitoring_namespace }
        }
        pod_selector {
          match_labels = var.network_policy.monitoring_pod_labels
        }
      }
      ports {
        port     = "9187"
        protocol = "TCP"
      }
    }
  }
}

resource "kubernetes_network_policy_v1" "database_egress" {
  metadata {
    name      = "${var.database.name}-egress"
    namespace = kubernetes_namespace_v1.notes.metadata[0].name
  }

  spec {
    pod_selector {
      match_labels = local.db_selector
    }
    policy_types = ["Egress"]

    # Kubernetes API server (instance manager).
    egress {
      dynamic "to" {
        for_each = local.api_server_ips
        content {
          ip_block {
            cidr = "${to.value}/32"
          }
        }
      }
      dynamic "ports" {
        for_each = local.api_server_ports
        content {
          port     = tostring(ports.value)
          protocol = "TCP"
        }
      }
    }

    # Other instances of the same cluster.
    egress {
      to {
        pod_selector {
          match_labels = local.db_selector
        }
      }
      ports {
        port     = "5432"
        protocol = "TCP"
      }
      ports {
        port     = "8000"
        protocol = "TCP"
      }
    }

    # DNS (the namespace-wide DNS policy only exists once the API chart is installed).
    egress {
      to {
        namespace_selector {
          match_labels = { "kubernetes.io/metadata.name" = var.network_policy.dns_namespace }
        }
        pod_selector {
          match_labels = var.network_policy.dns_pod_labels
        }
      }
      ports {
        port     = "53"
        protocol = "UDP"
      }
      ports {
        port     = "53"
        protocol = "TCP"
      }
    }
  }
}

# --- PostgreSQL (CloudNativePG, official `cluster` chart) -----------------------------------
resource "helm_release" "database" {
  name       = var.database.name
  repository = "https://cloudnative-pg.github.io/charts"
  chart      = "cluster"
  version    = var.database.chart_version
  namespace  = kubernetes_namespace_v1.notes.metadata[0].name
  timeout    = 600

  values = [yamlencode({
    fullnameOverride = var.database.name # Secret "<name>-app", label cnpg.io/cluster=<name>
    type             = "postgresql"
    mode             = "standalone"
    cluster = {
      instances = var.database.instances
      imageName = var.database.image
      storage = {
        size         = var.database.storage_size
        storageClass = var.database.storage_class
      }
      # The operator generates the app credentials in-cluster (Secret "<name>-app");
      # nothing secret passes through Terraform (ADR-0007). No superuser Secret at all.
      initdb                = { database = var.database.database, owner = var.database.owner }
      enableSuperuserAccess = false
      # A single-instance PDB would block draining the node that hosts the database.
      enablePDB = var.database.instances > 1
      monitoring = {
        enabled        = var.database.monitoring
        podMonitor     = { enabled = var.database.monitoring }
        prometheusRule = { enabled = var.database.monitoring }
      }
      resources = {
        requests = { cpu = "100m", memory = "256Mi" }
        limits   = { memory = "512Mi" }
      }
    }
  })]

  depends_on = [
    kubernetes_network_policy_v1.database_ingress,
    kubernetes_network_policy_v1.database_egress,
  ]
}

# Helm does not wait for custom resources, so without this gate the API release (and its
# pre-install migration Job) would start while PostgreSQL is still initialising.
resource "terraform_data" "database_ready" {
  triggers_replace = [helm_release.database.metadata.revision]

  provisioner "local-exec" {
    command = "kubectl --context ${var.kube_context} -n ${kubernetes_namespace_v1.notes.metadata[0].name} wait --for=condition=Ready cluster.postgresql.cnpg.io/${var.database.name} --timeout=600s"
  }
}

# --- Notes API ------------------------------------------------------------------------------
resource "helm_release" "api" {
  name        = local.api_release
  chart       = var.api.chart_path
  namespace   = kubernetes_namespace_v1.notes.metadata[0].name
  description = "chart-sha1=${local.api_chart_checksum}"
  timeout     = 600
  wait        = true

  values = concat(
    [for f in var.api.values_files : file(f)],
    [yamlencode(merge(
      {
        image = {
          repository = var.api.image.repository
          tag        = var.api.image.tag
          digest     = var.api.image.digest
        }
      },
      var.api.app_message == null ? {} : { config = { appMessage = var.api.app_message } },
    ))],
  )

  depends_on = [terraform_data.database_ready]
}
