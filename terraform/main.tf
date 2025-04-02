resource "random_password" "root_pass" {
  length  = 30
  special = true
}

resource "linode_instance" "gpu_server" {
  label            = var.node_label
  region           = var.region
  image            = var.image_name
  type             = var.image_type
  root_pass        = random_password.root_pass.result
  authorized_users = var.authorized_users
  metadata {
    user_data = filebase64("../cloud-init/gpu-server-config.yaml")
  }
}

resource "linode_firewall" "gpu_server_firewall" {
  label = "${var.node_label}-fw"

  inbound_policy  = "DROP"
  outbound_policy = "ACCEPT"

  inbound {
    label    = "allow-ssh-http-from-my-computer"
    action   = "ACCEPT"
    protocol = "TCP"
    ports    = "22,8888"
    ipv4     = var.allowed_ssh_user_ips
  }

  linodes = [linode_instance.gpu_server.id]
}