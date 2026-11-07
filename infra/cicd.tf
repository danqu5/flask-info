# Least-privilege permissions for the GitHub Actions pipeline.
#
# The policy document is always rendered and exported as an output, so
# a tester using static access keys can attach the same permissions to
# their own IAM user. When var.github_repository is set, an OIDC-trusted
# role is also created so the workflow can run without long-lived keys.

data "aws_caller_identity" "current" {}
data "aws_partition" "current" {}

locals {
  github_oidc_enabled = var.github_repository != ""
  github_subjects = length(var.github_oidc_subjects) > 0 ? var.github_oidc_subjects : [
    "repo:${var.github_repository}:ref:refs/heads/main",
  ]
  oidc_provider_arn = (
    local.github_oidc_enabled && var.create_github_oidc_provider
    ? aws_iam_openid_connect_provider.github[0].arn
    : "arn:${data.aws_partition.current.partition}:iam::${data.aws_caller_identity.current.account_id}:oidc-provider/token.actions.githubusercontent.com"
  )
}

data "aws_iam_policy_document" "deployer" {
  statement {
    sid       = "EcrAuth"
    actions   = ["ecr:GetAuthorizationToken"]
    resources = ["*"]
  }

  statement {
    sid = "PushAppImage"
    actions = [
      "ecr:BatchCheckLayerAvailability",
      "ecr:BatchGetImage",
      "ecr:CompleteLayerUpload",
      "ecr:DescribeRepositories",
      "ecr:GetDownloadUrlForLayer",
      "ecr:InitiateLayerUpload",
      "ecr:PutImage",
      "ecr:UploadLayerPart",
    ]
    resources = [aws_ecr_repository.app.arn]
  }

  # Read-only discovery: find the instance(s), ALB and target health by tag/name.
  # These Describe* APIs don't support resource-level permissions.
  statement {
    sid = "Discover"
    actions = [
      "ec2:DescribeInstances",
      "elasticloadbalancing:DescribeLoadBalancers",
      "elasticloadbalancing:DescribeTargetGroups",
      "elasticloadbalancing:DescribeTargetHealth",
      "ssm:DescribeInstanceInformation",
    ]
    resources = ["*"]
  }

  # Run Command: only the AWS-RunShellScript document...
  statement {
    sid       = "RunShellScriptDocument"
    actions   = ["ssm:SendCommand"]
    resources = ["arn:${data.aws_partition.current.partition}:ssm:${var.aws_region}::document/AWS-RunShellScript"]
  }

  # ...and only on instances that belong to this project.
  statement {
    sid       = "RunOnProjectInstancesOnly"
    actions   = ["ssm:SendCommand"]
    resources = ["arn:${data.aws_partition.current.partition}:ec2:${var.aws_region}:${data.aws_caller_identity.current.account_id}:instance/*"]

    condition {
      test     = "StringEquals"
      variable = "ssm:resourceTag/Project"
      values   = [var.project_name]
    }
  }

  statement {
    sid       = "ReadCommandResults"
    actions   = ["ssm:GetCommandInvocation", "ssm:ListCommandInvocations"]
    resources = ["*"]
  }
}

# --- Optional: GitHub OIDC role ---------------------------------------------

resource "aws_iam_openid_connect_provider" "github" {
  count          = local.github_oidc_enabled && var.create_github_oidc_provider ? 1 : 0
  url            = "https://token.actions.githubusercontent.com"
  client_id_list = ["sts.amazonaws.com"]
  # AWS no longer checks these for GitHub, but older providers require a value.
  thumbprint_list = [
    "6938fd4d98bab03faadb97b34396831e3780aea1",
    "1c58a3a8518e8759bf075b76b750d4f2df264fcd",
  ]
}

data "aws_iam_policy_document" "github_trust" {
  count = local.github_oidc_enabled ? 1 : 0

  statement {
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [local.oidc_provider_arn]
    }

    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:aud"
      values   = ["sts.amazonaws.com"]
    }

    condition {
      test     = "StringLike"
      variable = "token.actions.githubusercontent.com:sub"
      values   = local.github_subjects
    }
  }
}

resource "aws_iam_role" "github_deployer" {
  count              = local.github_oidc_enabled ? 1 : 0
  name               = "${var.project_name}-github-deployer"
  assume_role_policy = data.aws_iam_policy_document.github_trust[0].json
}

resource "aws_iam_role_policy" "github_deployer" {
  count  = local.github_oidc_enabled ? 1 : 0
  name   = "deploy"
  role   = aws_iam_role.github_deployer[0].id
  policy = data.aws_iam_policy_document.deployer.json
}
