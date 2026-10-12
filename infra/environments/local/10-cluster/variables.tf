variable "cluster_name" {
  description = "Name of the kind cluster."
  type        = string
}

variable "node_image" {
  description = "kindest/node image pinned by digest; Kubernetes minor matches the target EKS version."
  type        = string
}

variable "worker_count" {
  description = "Number of worker nodes."
  type        = number
}

variable "port_mappings" {
  description = "Host → node port mappings for the gateway NodePorts."
  type = map(object({
    container_port = number
    host_port      = number
    listen_address = optional(string, "127.0.0.1")
    protocol       = optional(string, "TCP")
  }))
}

variable "pod_subnet" {
  description = "Pod CIDR, shared with the CNI configuration in 20-platform."
  type        = string
}

variable "registry_image" {
  description = "Registry image pinned by digest."
  type        = string
}

variable "registry_host_port" {
  description = "Host port of the local registry (images are pushed to localhost:<port>)."
  type        = number
}

variable "kubeconfig_path" {
  description = "Kubeconfig the cluster context is merged into; ~ is expanded."
  type        = string
  default     = "~/.kube/config"
}

variable "docker_host" {
  description = "Docker daemon socket for the docker provider. null uses DOCKER_HOST or the default socket."
  type        = string
  default     = null
}

variable "labels" {
  description = "Labels applied to Docker resources."
  type        = map(string)
  default     = {}
}
