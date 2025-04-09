variable "node_label" {
  type        = string
  description = "Label for the compute instance"
  default     = "jupyter-stack"
}

variable "region" {
  type        = string
  description = "Linode region to deploy"
  default     = "us-ord"
}

variable "image_name" {
  type        = string
  description = "The image to deploy"
  # Only certain images are compatible with cloud-init by default.
  # Refer to the guide below for compatible platform provided images 
  # https://techdocs.akamai.com/cloud-computing/docs/overview-of-the-metadata-service#availability
  default = "linode/ubuntu24.04"
}

variable "image_type" {
  type        = string
  description = "The image type to deploy"
  default     = "g2-gpu-rtx4000a1-s"
}

variable "project_name" {
  type        = string
  description = "Specifies the name of the docker container for running Jupyter Lab"
  default     = "jupyter-lab-docker"
}

variable "notebook_data_volume_name" {
  type        = string
  description = "Specifies the name of the docker volume to use for notebook data"
  default     = "notebook-data"
}

variable "cert_volume_name" {
  type        = string
  description = "Specifies the name of the docker volume to use for TLS certificates"
  default     = "cert-data"
}

variable "jupyter_lab_host_port" {
  type        = string
  description = "The port that Jupyter Lab listens on the GPU server"
  default     = "8888"
}

variable "deployment_state" {
  type = string
  description = "Used to trigger unique deployment values depending on if running terraform during initial deploy or after deployment"
  default = "initial_deploy"
  validation {
    condition = can(regex("initial_deploy|post_deploy", var.deployment_state))
    error_message = "Valid values are \"initial_deploy\" or \"post_deploy\""
  }
}

# Configure the below via tfvars file, environment variables, etc.

variable "authorized_users" {
  type        = list(string)
  description = "List of users who has SSH keys imported into cloud manager who need access"
}

variable "allowed_ssh_user_ips" {
  type        = list(string)
  description = "List of IP addresses that can SSH into the server"
}

variable "ssl_cert_fqdn" {
  type        = string
  description = "Domain name for accessing the Jupyter Lab UI"
}

variable "ssl_cert_email" {
  type        = string
  description = "Email address to use for Let's Encrypt request"
}

variable "linode_domain_id" {
  type        = number
  description = "The primary key for the DNS zone"
}