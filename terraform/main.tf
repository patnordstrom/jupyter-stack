resource "random_password" "root_pass" {
  length  = 30
  special = true
}

resource "random_password" "jupyter_lab_pass" {
  length           = 30
  special          = true
  override_special = "!@#%^*"
}

resource "linode_nodebalancer" "gpu_server_ingress" {
  label  = "${var.node_label}-ingress"
  region = var.region
}

resource "linode_nodebalancer_config" "gpu_server_ingress_port80" {
  nodebalancer_id = linode_nodebalancer.gpu_server_ingress.id
  port            = 80
  protocol        = "tcp"
  algorithm       = "roundrobin"
  stickiness      = "none"
  check           = "none"
  check_passive   = false

}

resource "linode_nodebalancer_node" "gpu_server_ingress_port80_backend" {
  nodebalancer_id = linode_nodebalancer.gpu_server_ingress.id
  config_id       = linode_nodebalancer_config.gpu_server_ingress_port80.id
  label           = "letsencrypt-cert-challenge"
  address         = "${linode_instance.gpu_server.private_ip_address}:8080"
  weight          = 100
  mode            = "accept"
}

resource "linode_nodebalancer_config" "gpu_server_ingress_port443" {
  nodebalancer_id = linode_nodebalancer.gpu_server_ingress.id
  port            = 443
  protocol        = "tcp"
  algorithm       = "roundrobin"
  stickiness      = "none"
  check           = "none"
  check_passive   = false

}

resource "linode_nodebalancer_node" "gpu_server_ingress_port443_backend" {
  nodebalancer_id = linode_nodebalancer.gpu_server_ingress.id
  config_id       = linode_nodebalancer_config.gpu_server_ingress_port443.id
  label           = "jupyter-lab-web-ui"
  address         = "${linode_instance.gpu_server.private_ip_address}:${var.jupyter_lab_host_port}"
  weight          = 100
  mode            = "accept"
}

resource "linode_domain_record" "jupyter_lab_dns_a" {
  domain_id   = var.linode_domain_id
  name        = split(".", var.ssl_cert_fqdn)[0]
  record_type = "A"
  target      = linode_nodebalancer.gpu_server_ingress.ipv4
  ttl_sec     = 30
  provisioner "local-exec" {
    command = "./scripts/wait_for_dns_propagation.sh"
    environment = {
      DOMAIN = var.ssl_cert_fqdn
      IP     = linode_nodebalancer.gpu_server_ingress.ipv4
    }
  }
}

resource "linode_domain_record" "jupyter_lab_dns_aaaa" {
  domain_id   = var.linode_domain_id
  name        = split(".", var.ssl_cert_fqdn)[0]
  record_type = "AAAA"
  target      = linode_nodebalancer.gpu_server_ingress.ipv6
  ttl_sec     = 30
}


data "template_file" "gpu_server_config" {
  template = file("${path.module}/templates/gpu-server-config.yaml")
  vars = {
    project_name              = var.project_name
    notebook_data_volume_name = var.notebook_data_volume_name
    cert_volume_name          = var.cert_volume_name
    ssl_cert_fqdn             = var.ssl_cert_fqdn
    ssl_cert_email            = var.ssl_cert_email
    jupyter_lab_host_port     = var.jupyter_lab_host_port
    jupyter_lab_web_pwd       = random_password.jupyter_lab_pass.result
  }
}

resource "linode_instance" "gpu_server" {
  label            = var.node_label
  region           = var.region
  image            = var.image_name
  type             = var.image_type
  root_pass        = random_password.root_pass.result
  authorized_users = var.authorized_users
  metadata {
    user_data = base64encode(data.template_file.gpu_server_config.rendered)
  }

  private_ip = true

  depends_on = [linode_domain_record.jupyter_lab_dns_a]

}

resource "linode_firewall" "gpu_server_firewall" {
  label = "${var.node_label}-fw"

  inbound_policy  = "DROP"
  outbound_policy = "ACCEPT"

  inbound {
    label    = "allow-ssh-from-my-computer"
    action   = "ACCEPT"
    protocol = "TCP"
    ports    = "22"
    ipv4     = var.allowed_ssh_user_ips
  }

  inbound {
    label    = "allow-from-from-nb"
    action   = "ACCEPT"
    protocol = "TCP"
    ports    = "8080,8888"
    ipv4     = ["192.168.255.0/24"]
  }

  linodes = [linode_instance.gpu_server.id]
}

resource "linode_firewall" "ingress_firewall" {
  label = "${var.node_label}-ingress-fw"

  inbound_policy  = "DROP"
  outbound_policy = "ACCEPT"

  inbound {
    label    = "allow-jupyter-from-my-computer"
    action   = "ACCEPT"
    protocol = "TCP"
    ports    = "443"
    ipv4     = var.allowed_ssh_user_ips
  }

  inbound {
    label    = "allow-http-cert-challenge"
    action   = "ACCEPT"
    protocol = "TCP"
    ports    = "80"
    ipv4     = ["0.0.0.0/0"]
    ipv6     = ["::/0"]
  }

  nodebalancers = [linode_nodebalancer.gpu_server_ingress.id]
}