output "api_url" {
  description = "Public URL of the Notes API through the gateway."
  value       = "https://api.${local.platform.gateway.domain}"
}

output "namespace" {
  description = "Namespace of the API and database."
  value       = module.notes_app.namespace
}

output "database" {
  description = "Database cluster, credentials Secret and read-write Service (all in-cluster only)."
  value       = module.notes_app.database
}

output "api_release" {
  description = "Notes API release and the exact image it runs."
  value       = module.notes_app.api_release
}
