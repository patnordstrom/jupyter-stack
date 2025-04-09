# We only want to allow port 80 through the nodebalancer initially when deploying
# so we can allow the Let's Encrypt http challenge to work
locals {
  nb_firewall_rule_letsencrypt = (var.deployment_state == "initial_deploy" ? "ACCEPT" : "DROP")
}

resource "random_password" "root_pass" {
  length  = 30
  special = true
}

# We auto generate the password you will login to Juypyter Lab
# You can fetch from the state and it is supplied as output at the end of the run
resource "random_password" "jupyter_lab_pass" {
  length           = 30
  special          = true
  override_special = "!@#%^*"
}

# Create the Nodebalancer resource
resource "linode_nodebalancer" "gpu_server_ingress" {
  label  = "${var.node_label}-ingress"
  region = var.region
}

# This enables port 80 on the Nodebalancer for the Let's Encrypt challenge
# For all of these Nodebalancer configs we just use TCP pass-thru and
# we also turn health checks off since some of the actions are short lived
resource "linode_nodebalancer_config" "gpu_server_ingress_port80" {
  nodebalancer_id = linode_nodebalancer.gpu_server_ingress.id
  port            = 80
  protocol        = "tcp"
  algorithm       = "roundrobin"
  stickiness      = "none"
  check           = "none"
  check_passive   = false

}

# This maps to port 8080 on the GPU server where certbot will be listening
resource "linode_nodebalancer_node" "gpu_server_ingress_port80_backend" {
  nodebalancer_id = linode_nodebalancer.gpu_server_ingress.id
  config_id       = linode_nodebalancer_config.gpu_server_ingress_port80.id
  label           = "letsencrypt-cert-challenge"
  address         = "${linode_instance.gpu_server.private_ip_address}:8080"
  weight          = 100
  mode            = "accept"
}

# This is the HTTPS ingreass for Jupyter Lab
resource "linode_nodebalancer_config" "gpu_server_ingress_port443" {
  nodebalancer_id = linode_nodebalancer.gpu_server_ingress.id
  port            = 443
  protocol        = "tcp"
  algorithm       = "roundrobin"
  stickiness      = "none"
  check           = "none"
  check_passive   = false

}

# This maps to the Jupyter lab port on the backend (typicall port 8888)
resource "linode_nodebalancer_node" "gpu_server_ingress_port443_backend" {
  nodebalancer_id = linode_nodebalancer.gpu_server_ingress.id
  config_id       = linode_nodebalancer_config.gpu_server_ingress_port443.id
  label           = "jupyter-lab-web-ui"
  address         = "${linode_instance.gpu_server.private_ip_address}:${var.jupyter_lab_host_port}"
  weight          = 100
  mode            = "accept"
}

# We create the DNS A record to point to the Nodebalancer
# The provisioner interrogates the name server to wait for 
# DNS propagation before continuing since that is needed for Let's Encrypt
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

# This is the template for cloud-init for configuring the GPU server
# with it's dependencies and our custom bootstrap script that
# provisions the certficates, volumes, and configurations for the pytorch container
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

# This deploys the GPU server as soon as the DNS is propagated
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

# GPU server will accept SSH from your computer (allowed IPs defined in tfvars)
# We also whitelist the Nodebalancer subnet so it can connect to our instance
# on the required ports (port 8080 for Let's Encrypt challenge / port 8888 for Jupyter Lab by default)
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
    ports    = "8080,${var.jupyter_lab_host_port}"
    ipv4     = ["192.168.255.0/24"]
  }

  linodes = [linode_instance.gpu_server.id]

}

# Firewall for the Nodebalancer that allows port 443 for Jupyter Lab
# and port 80 is conditional.  When deployment_state is set to "initial_deploy"
# we ACCEPT connections to allow Let's Encrypt challenge.  The idea is that once
# terraform runs the first time we can then run it a 2nd time after and set 
# deployment_state to "post_deploy" which will turn off port 80 access
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
    action   = local.nb_firewall_rule_letsencrypt
    protocol = "TCP"
    ports    = "80"
    ipv4     = ["0.0.0.0/0"]
    ipv6     = ["::/0"]
  }

  nodebalancers = [linode_nodebalancer.gpu_server_ingress.id]
}

# This is the final task which waits for Jupyter Lab endpoint to return HTTP 200
# Once ready it will output the URL and Password to access
# The whole terraform run end-to-end takes about 10 minutes
resource "terraform_data" "wait_for_jupyter_lab_endpoint_ready" {
  provisioner "local-exec" {
    command = "./scripts/wait_for_jupyter_https_ready.sh"
    environment = {
      ENDPOINT = "https://${var.ssl_cert_fqdn}/login"
    }
  }

  depends_on = [ linode_instance.gpu_server ]
}