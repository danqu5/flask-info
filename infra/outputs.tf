output "app_url" {
  description = "Public URL of the /info endpoint (through the ALB)."
  value       = "http://${aws_lb.app.dns_name}/info"
}

output "alb_dns_name" {
  value = aws_lb.app.dns_name
}

output "instance_id" {
  value = aws_instance.app.id
}

output "instance_public_ip" {
  description = "For SSH from ssh_allowed_cidr only. The app port is NOT reachable on this IP."
  value       = aws_instance.app.public_ip
}

output "ecr_repository_url" {
  description = "Push images here from CI/CD."
  value       = aws_ecr_repository.app.repository_url
}

output "instance_role_arn" {
  value = aws_iam_role.app.arn
}

output "github_deployer_role_arn" {
  description = "Set as the AWS_ROLE_ARN variable in GitHub (only when github_repository is set)."
  value       = one(aws_iam_role.github_deployer[*].arn)
}

output "deployer_policy_json" {
  description = "Least-privilege policy for the CI pipeline. Attach it to an IAM user/role if you use access keys instead of OIDC."
  value       = data.aws_iam_policy_document.deployer.json
}
