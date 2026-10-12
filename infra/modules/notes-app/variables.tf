variable "namespace" {
  description = "Namespace for the API and its database (Pod Security restricted)."
  type        = string
  default     = "notes"
}

variable "gateway_access_label" {
  description = "Label (key) that lets a namespace attach routes to the shared Gateway (from 20-platform)."
  type        = string
}

variable "kube_context" {
  description = "kubectl context used only to wait for the database to become Ready (Helm does not wait for custom resources)."
  type        = string
}

variable "database" {
  description = "CloudNativePG cluster, deployed with the official `cluster` chart."
  type = object({
    name          = optional(string, "notes-db")
    chart_version = string
    image         = string
    instances     = optional(number, 1)
    storage_size  = optional(string, "2Gi")
    storage_class = optional(string, "")
    database      = optional(string, "app")
    owner         = optional(string, "app")
    monitoring    = optional(bool, true)
  })

  validation {
    condition     = can(regex("@sha256:[a-f0-9]{64}$", var.database.image))
    error_message = "database.image must be pinned by digest."
  }

  validation {
    condition     = var.database.instances >= 1 && var.database.instances <= 5
    error_message = "database.instances must be between 1 and 5."
  }
}

variable "api" {
  description = "Notes API Helm release (charts/notes-api)."
  type = object({
    chart_path   = string
    values_files = list(string)
    image = object({
      repository = string
      tag        = string
      digest     = optional(string, "")
    })
    app_message = optional(string)
  })

  validation {
    condition     = can(regex("^[0-9a-f]{7,40}(-dirty)?$", var.api.image.tag))
    error_message = "api.image.tag must be a git SHA (optionally with -dirty), never a mutable tag like latest."
  }

  validation {
    condition     = var.api.image.digest == "" || can(regex("^sha256:[a-f0-9]{64}$", var.api.image.digest))
    error_message = "api.image.digest must be empty or sha256:<64 hex>."
  }
}

variable "network_policy" {
  description = "Peers allowed to reach the database pods, and the Kubernetes API endpoints they may call."
  type = object({
    operator_namespace = optional(string, "cnpg-system")
    operator_pod_labels = optional(map(string), {
      "app.kubernetes.io/name" = "cloudnative-pg"
    })
    monitoring_namespace = optional(string, "monitoring")
    monitoring_pod_labels = optional(map(string), {
      "app.kubernetes.io/name" = "prometheus"
    })
    dns_namespace  = optional(string, "kube-system")
    dns_pod_labels = optional(map(string), { "k8s-app" = "kube-dns" })
  })
  default = {}
}

variable "labels" {
  description = "Labels added to the namespace."
  type        = map(string)
  default     = {}
}
