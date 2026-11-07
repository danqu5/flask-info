# --- Credentials / account ---------------------------------------------------

variable "aws_region" {
  description = "AWS region to deploy into."
  type        = string
  default     = "us-east-2"
}

variable "aws_profile" {
  description = "Optional named AWS CLI profile. Leave null to use the default credential chain (env vars, AWS_PROFILE, SSO, instance role, ...)."
  type        = string
  default     = null
}

variable "assume_role_arn" {
  description = "Optional IAM role ARN for Terraform to assume before creating resources."
  type        = string
  default     = null
}

variable "assume_role_external_id" {
  description = "Optional external ID used with assume_role_arn."
  type        = string
  default     = null
}

# --- General -----------------------------------------------------------------

variable "project_name" {
  description = "Name prefix for all resources."
  type        = string
  default     = "flask-info"

  validation {
    condition     = can(regex("^[a-z0-9-]{3,24}$", var.project_name))
    error_message = "project_name must be 3-24 chars of lowercase letters, digits and hyphens (it is used in ALB/target group names)."
  }
}

# --- Network -----------------------------------------------------------------

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

# --- Compute -----------------------------------------------------------------

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
  description = "ECR image tag the instance runs. The CI/CD pipeline pushes this tag."
  type        = string
  default     = "latest"
}

variable "enable_ssm" {
  description = "Give the instance the minimal SSM agent permissions needed for Run Command. The GitHub Actions deploy uses this; disable only if you deploy another way."
  type        = bool
  default     = true
}

# --- CI/CD (GitHub Actions) ----------------------------------------------------

variable "github_repository" {
  description = "Optional 'owner/repo'. When set, creates an IAM role that GitHub Actions in that repo can assume via OIDC (no long-lived keys)."
  type        = string
  default     = ""

  validation {
    condition     = var.github_repository == "" || can(regex("^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$", var.github_repository))
    error_message = "github_repository must look like 'owner/repo'."
  }
}

variable "github_oidc_subjects" {
  description = "OIDC 'sub' patterns allowed to assume the deploy role. Defaults to the main branch of github_repository."
  type        = list(string)
  default     = []
}

variable "create_github_oidc_provider" {
  description = "Create the GitHub OIDC identity provider. Set false if your account already has token.actions.githubusercontent.com (only one is allowed per account)."
  type        = bool
  default     = true
}
