locals {
  context_name       = "kind-${var.cluster_name}"
  kubernetes_version = regex("^kindest/node:(v[0-9]+\\.[0-9]+\\.[0-9]+)@", var.node_image)[0]

  registry_host        = "localhost:${var.registry.host_port}"
  registry_in_cluster  = "${var.registry.name}:5000"
  containerd_certs_dir = "${var.generated_dir}/containerd-certs.d"

  # Every node mounts the generated registry config read-only (declarative replacement for
  # the `docker exec ... hosts.toml` step in kind's local-registry guide).
  certs_mount = {
    host_path      = local.containerd_certs_dir
    container_path = "/etc/containerd/certs.d"
    read_only      = true
  }

  labels = merge(var.labels, {
    "app.kubernetes.io/managed-by" = "terraform"
    "app.kubernetes.io/part-of"    = var.cluster_name
  })
}

# kind attaches its nodes to an existing network with this name instead of creating one,
# so `terraform destroy` removes the network too (kind itself never deletes it).
resource "docker_network" "kind" {
  name   = var.network_name
  driver = "bridge"
  options = {
    "com.docker.network.bridge.enable_ip_masquerade" = "true"
  }

  dynamic "labels" {
    for_each = local.labels
    content {
      label = labels.key
      value = labels.value
    }
  }
}

resource "docker_image" "registry" {
  name         = var.registry.image
  keep_locally = false
}

resource "docker_container" "registry" {
  name           = var.registry.name
  image          = docker_image.registry.image_id
  restart        = "always"
  must_run       = true
  remove_volumes = true

  ports {
    internal = 5000
    external = var.registry.host_port
    ip       = "127.0.0.1"
  }

  networks_advanced {
    name = docker_network.kind.name
  }

  dynamic "labels" {
    for_each = local.labels
    content {
      label = labels.key
      value = labels.value
    }
  }
}

resource "local_file" "registry_hosts" {
  filename             = "${local.containerd_certs_dir}/${local.registry_host}/hosts.toml"
  content              = "[host.\"http://${local.registry_in_cluster}\"]\n"
  file_permission      = "0644"
  directory_permission = "0755"
}

resource "kind_cluster" "this" {
  name            = var.cluster_name
  node_image      = var.node_image
  kubeconfig_path = var.kubeconfig_path
  # Must stay false while the default CNI is disabled: nodes are NotReady until 20-platform.
  wait_for_ready = false

  kind_config {
    kind        = "Cluster"
    api_version = "kind.x-k8s.io/v1alpha4"

    containerd_config_patches = [
      <<-TOML
      [plugins."io.containerd.grpc.v1.cri".registry]
        config_path = "/etc/containerd/certs.d"
      TOML
    ]

    networking {
      disable_default_cni = var.disable_default_cni
      pod_subnet          = var.pod_subnet
      service_subnet      = var.service_subnet
    }

    node {
      role = "control-plane"

      dynamic "extra_port_mappings" {
        for_each = var.port_mappings
        content {
          container_port = extra_port_mappings.value.container_port
          host_port      = extra_port_mappings.value.host_port
          listen_address = extra_port_mappings.value.listen_address
          protocol       = extra_port_mappings.value.protocol
        }
      }

      extra_mounts {
        host_path      = local.certs_mount.host_path
        container_path = local.certs_mount.container_path
        read_only      = local.certs_mount.read_only
      }
    }

    dynamic "node" {
      for_each = range(var.worker_count)
      content {
        role = "worker"

        extra_mounts {
          host_path      = local.certs_mount.host_path
          container_path = local.certs_mount.container_path
          read_only      = local.certs_mount.read_only
        }
      }
    }
  }

  depends_on = [docker_network.kind, local_file.registry_hosts]
}
