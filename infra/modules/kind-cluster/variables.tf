variable "cluster_name" {
  description = "Name of the kind cluster. The kubectl context becomes kind-<cluster_name>."
  type        = string

  validation {
    condition     = can(regex("^[a-z0-9]([-a-z0-9]{0,30}[a-z0-9])?$", var.cluster_name))
    error_message = "cluster_name must be lowercase alphanumeric or '-', 1-32 characters."
  }
}

variable "node_image" {
  description = "kindest/node image for every node, pinned by digest. Must be published for the kind version embedded in the provider, and match the EKS Kubernetes minor."
  type        = string

  validation {
    condition     = can(regex("^kindest/node:v[0-9]+\\.[0-9]+\\.[0-9]+@sha256:[a-f0-9]{64}$", var.node_image))
    error_message = "node_image must look like kindest/node:vX.Y.Z@sha256:<digest>."
  }
}

variable "worker_count" {
  description = "Number of worker nodes (in addition to the single control-plane node)."
  type        = number
  default     = 2

  validation {
    condition     = var.worker_count >= 0 && var.worker_count <= 5 && floor(var.worker_count) == var.worker_count
    error_message = "worker_count must be a whole number between 0 and 5."
  }
}

variable "port_mappings" {
  description = "Host ports forwarded to control-plane node ports, keyed by a name (e.g. http, https). container_port is the NodePort the gateway listens on."
  type = map(object({
    container_port = number
    host_port      = number
    listen_address = optional(string, "127.0.0.1")
    protocol       = optional(string, "TCP")
  }))
  default = {}

  validation {
    condition = alltrue([
      for m in values(var.port_mappings) :
      m.container_port >= 1 && m.container_port <= 65535 && m.host_port >= 1 && m.host_port <= 65535
    ])
    error_message = "All ports must be between 1 and 65535."
  }

  validation {
    condition     = alltrue([for m in values(var.port_mappings) : contains(["TCP", "UDP", "SCTP"], m.protocol)])
    error_message = "protocol must be TCP, UDP or SCTP."
  }
}

variable "disable_default_cni" {
  description = "Disable kindnet so a NetworkPolicy-enforcing CNI (Calico, ADR-0005) can be installed. Nodes stay NotReady until it is."
  type        = bool
  default     = true
}

variable "pod_subnet" {
  description = "Pod CIDR. The CNI installed in 20-platform must use the same range."
  type        = string
  default     = "10.244.0.0/16"

  validation {
    condition     = can(cidrnetmask(var.pod_subnet))
    error_message = "pod_subnet must be a valid IPv4 CIDR."
  }
}

variable "service_subnet" {
  description = "Service CIDR."
  type        = string
  default     = "10.96.0.0/12"

  validation {
    condition     = can(cidrnetmask(var.service_subnet))
    error_message = "service_subnet must be a valid IPv4 CIDR."
  }
}

variable "network_name" {
  description = "Docker network shared by the kind nodes and the registry. kind reuses an existing network with this name, so Terraform owns its lifecycle."
  type        = string
  default     = "kind"
}

variable "registry" {
  description = "Local image registry (the ECR stand-in). Nodes pull localhost:<host_port>/<image> through a containerd mirror to http://<name>:5000."
  type = object({
    image     = string
    name      = optional(string, "kind-registry")
    host_port = optional(number, 5001)
  })

  validation {
    condition     = can(regex("@sha256:[a-f0-9]{64}$", var.registry.image))
    error_message = "registry.image must be pinned by digest."
  }
}

variable "kubeconfig_path" {
  description = "Absolute path of the kubeconfig file the cluster context is merged into. The context is removed again on destroy."
  type        = string

  validation {
    condition     = startswith(var.kubeconfig_path, "/")
    error_message = "kubeconfig_path must be absolute (use pathexpand() in the root stack)."
  }
}

variable "generated_dir" {
  description = "Absolute directory where generated node config (containerd registry hosts) is written. It must be visible to the Docker daemon, e.g. under $HOME with Colima or Docker Desktop."
  type        = string

  validation {
    condition     = startswith(var.generated_dir, "/")
    error_message = "generated_dir must be an absolute path."
  }
}

variable "labels" {
  description = "Labels applied to the Docker resources created by this module."
  type        = map(string)
  default     = {}
}
