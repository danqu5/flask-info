variable "aws_region" {
  description = "AWS region to deploy into."
  type        = string
  default     = "us-east-2"
}

variable "project_name" {
  description = "Name prefix for all resources."
  type        = string
  default     = "flask-info"

  validation {
    condition     = can(regex("^[a-z0-9-]{3,24}$", var.project_name))
    error_message = "project_name must be 3-24 chars of lowercase letters, digits and hyphens (it is used in ALB/target group names)."
  }
}

variable "vpc_cidr" {
  description = "CIDR block for the VPC."
  type        = string
  default     = "10.20.0.0/16"
}

variable "ssh_allowed_cidr" {
  description = "The only CIDR allowed to SSH to the instance. Set to your own IP as x.x.x.x/32."
  type        = string
  default     = "1.2.3.4/32"

  validation {
    condition     = can(cidrhost(var.ssh_allowed_cidr, 0)) && var.ssh_allowed_cidr != "0.0.0.0/0"
    error_message = "ssh_allowed_cidr must be a valid CIDR and must not be 0.0.0.0/0."
  }
}

variable "instance_type" {
  description = "EC2 instance type."
  type        = string
  default     = "t3.micro"
}

variable "ssh_public_key" {
  description = "Optional SSH public key (contents, e.g. 'ssh-ed25519 AAAA...'). If empty, no key pair is attached."
  type        = string
  default     = ""
}

variable "app_port" {
  description = "Port the container listens on (host port is the same)."
  type        = number
  default     = 5000
}

variable "image_tag" {
  description = "ECR image tag the instance runs on first boot. The CI/CD pipeline also pushes this tag."
  type        = string
  default     = "latest"
}
