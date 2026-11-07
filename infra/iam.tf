# The instance only needs to pull its image from ONE ECR repository.
# ecr:GetAuthorizationToken can't be scoped to a resource (AWS limitation);
# every other action is limited to this repository's ARN.

data "aws_iam_policy_document" "ec2_assume" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "app" {
  name               = "${var.project_name}-ec2-role"
  assume_role_policy = data.aws_iam_policy_document.ec2_assume.json
}

data "aws_iam_policy_document" "ecr_pull" {
  statement {
    sid       = "EcrAuth"
    actions   = ["ecr:GetAuthorizationToken"]
    resources = ["*"]
  }

  statement {
    sid = "PullAppImageOnly"
    actions = [
      "ecr:BatchCheckLayerAvailability",
      "ecr:BatchGetImage",
      "ecr:GetDownloadUrlForLayer",
    ]
    resources = [aws_ecr_repository.app.arn]
  }
}

resource "aws_iam_role_policy" "ecr_pull" {
  name   = "ecr-pull-app-image"
  role   = aws_iam_role.app.id
  policy = data.aws_iam_policy_document.ecr_pull.json
}

# Lets the pre-installed SSM agent register and receive Run Command, which the
# CI/CD pipeline uses to deploy (GitHub runner IPs vary, so SSH from CI would
# mean opening port 22 wide). This is a trimmed subset of
# AmazonSSMManagedInstanceCore: no Parameter Store, inventory, patching or
# association permissions.
data "aws_iam_policy_document" "ssm_run_command" {
  statement {
    sid       = "SsmAgentRegistration"
    actions   = ["ssm:UpdateInstanceInformation"]
    resources = ["*"]
  }

  statement {
    sid = "SsmAgentMessaging"
    actions = [
      "ssmmessages:CreateControlChannel",
      "ssmmessages:CreateDataChannel",
      "ssmmessages:OpenControlChannel",
      "ssmmessages:OpenDataChannel",
      "ec2messages:AcknowledgeMessage",
      "ec2messages:DeleteMessage",
      "ec2messages:FailMessage",
      "ec2messages:GetEndpoint",
      "ec2messages:GetMessages",
      "ec2messages:SendReply",
    ]
    resources = ["*"]
  }
}

resource "aws_iam_role_policy" "ssm_run_command" {
  count  = var.enable_ssm ? 1 : 0
  name   = "ssm-run-command"
  role   = aws_iam_role.app.id
  policy = data.aws_iam_policy_document.ssm_run_command.json
}

resource "aws_iam_instance_profile" "app" {
  name = "${var.project_name}-ec2-profile"
  role = aws_iam_role.app.name
}
