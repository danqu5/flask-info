# IAM user for the GitHub Actions pipeline, with only the permissions a deploy
# needs. Its access key goes into the repo's AWS_ACCESS_KEY_ID /
# AWS_SECRET_ACCESS_KEY secrets (see the ci_* outputs).
#
# Note: the secret key is stored in Terraform state in plaintext. Keep state
# private (it is gitignored here); use an encrypted remote backend on a team.

data "aws_caller_identity" "current" {}
data "aws_partition" "current" {}

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

resource "aws_iam_user" "ci" {
  name = "${var.project_name}-github-ci"
}

resource "aws_iam_user_policy" "ci" {
  name   = "deploy"
  user   = aws_iam_user.ci.name
  policy = data.aws_iam_policy_document.deployer.json
}

resource "aws_iam_access_key" "ci" {
  user = aws_iam_user.ci.name
}

# These resources used to be optional (count = 0/1). The moved blocks keep the
# existing user and key, so the secrets already in GitHub stay valid.
moved {
  from = aws_iam_user.ci[0]
  to   = aws_iam_user.ci
}

moved {
  from = aws_iam_user_policy.ci[0]
  to   = aws_iam_user_policy.ci
}

moved {
  from = aws_iam_access_key.ci[0]
  to   = aws_iam_access_key.ci
}
