terraform {
  required_version = ">= 1.5.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.30, < 7.0"
    }
  }
}

# ---------------------------------------------------------------------------
# Credentials
#
# Nothing is hardcoded. The provider resolves credentials through the
# standard AWS chain, so any of these work without editing code:
#   * env vars:      AWS_ACCESS_KEY_ID / AWS_SECRET_ACCESS_KEY / AWS_SESSION_TOKEN
#   * named profile: AWS_PROFILE=foo, or -var aws_profile=foo
#   * SSO:           aws sso login --profile foo, then as above
#   * instance/container role, web identity (CI OIDC), etc.
# Optionally assume a role in the target account with -var assume_role_arn=...
# ---------------------------------------------------------------------------
provider "aws" {
  region  = var.aws_region
  profile = var.aws_profile

  dynamic "assume_role" {
    for_each = var.assume_role_arn == null ? [] : [var.assume_role_arn]
    content {
      role_arn     = assume_role.value
      session_name = "${var.project_name}-terraform"
      external_id  = var.assume_role_external_id
    }
  }

  default_tags {
    tags = {
      Project   = var.project_name
      ManagedBy = "terraform"
    }
  }
}
