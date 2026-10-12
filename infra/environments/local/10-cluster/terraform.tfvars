# Local environment values. Not secret — committed on purpose (no credentials ever go here).
cluster_name = "notes-local"

# kind v0.31.0 (embedded in tehcyx/kind 0.11.0) default image; Kubernetes 1.35 = target EKS minor.
node_image   = "kindest/node:v1.35.0@sha256:452d707d4862f52530247495d180205e029056831160e22870e37e3f6c1ac31f"
worker_count = 2
pod_subnet   = "10.244.0.0/16"

# Envoy Gateway's proxy Service will use these NodePorts in 20-platform.
port_mappings = {
  http  = { container_port = 30080, host_port = 80 }
  https = { container_port = 30443, host_port = 443 }
}

registry_image     = "registry:3.1.2@sha256:ddf754342cfc8acc51a56d5d0ab6af06826461864460636d8bd5c546dab2a7b8"
registry_host_port = 5001

labels = {
  project     = "aws-challenge"
  environment = "local"
}
