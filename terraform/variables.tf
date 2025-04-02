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

# Configure the below via tfvars file, environment variables, etc.

variable "authorized_users" {
  type        = list(string)
  description = "List of users who has SSH keys imported into cloud manager who need access"
}

variable "allowed_ssh_user_ips" {
  type        = list(string)
  description = "List of IP addresses that can SSH into the server"
}