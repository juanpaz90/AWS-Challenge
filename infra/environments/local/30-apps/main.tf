module "notes_app" {
  source = "../../../modules/notes-app"

  namespace            = "notes"
  gateway_access_label = local.platform.gateway.namespace_label_key
  kube_context         = local.cluster.context_name
  labels               = var.labels

  database = {
    name          = "notes-db"
    chart_version = var.cnpg_cluster_chart_version
    image         = var.postgres_image
    instances     = 1 # local: one instance on local-path storage (3 + S3 backups on AWS, ADR-0004)
    storage_size  = var.database_storage_size
    storage_class = "standard" # kind's local-path provisioner
  }

  api = {
    chart_path = abspath("${path.module}/../../../../charts/notes-api")
    values_files = [
      abspath("${path.module}/../../../../charts/notes-api/values-local.yaml"),
    ]
    image = {
      repository = "${local.cluster.registry_host}/notes-api"
      tag        = var.image_tag
      digest     = var.image_digest
    }
    app_message = var.app_message
  }
}
