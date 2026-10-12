variable "image_tag" {
  description = "Notes API image tag (git SHA). Set by `task apps:up` after building and pushing the image; there is no default on purpose."
  type        = string
}

variable "image_digest" {
  description = "Digest of the pushed image (sha256:...). When set the release pins it, so a rebuilt '-dirty' tag can never be served stale."
  type        = string
  default     = ""
}

variable "app_message" {
  description = "Optional override of the API's message (GET /), used to demo a configuration change and rolling update."
  type        = string
  default     = null
}

variable "cnpg_cluster_chart_version" {
  description = "Version of the CloudNativePG `cluster` chart."
  type        = string
}

variable "postgres_image" {
  description = "PostgreSQL operand image, pinned by digest."
  type        = string
}

variable "database_storage_size" {
  description = "PVC size of each PostgreSQL instance."
  type        = string
}

variable "labels" {
  description = "Labels added to the notes namespace."
  type        = map(string)
  default     = {}
}
