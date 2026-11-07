output "app_url" {
  description = "Public URL of the /info endpoint (through the ALB)."
  value       = "http://${aws_lb.app.dns_name}/info"
}

output "instance_id" {
  value = aws_instance.app.id
}

output "instance_public_ip" {
  description = "For SSH from ssh_allowed_cidr only. The app port is NOT reachable on this IP."
  value       = aws_instance.app.public_ip
}

output "ecr_repository_url" {
  value = aws_ecr_repository.app.repository_url
}

output "ci_access_key_id" {
  description = "GitHub secret AWS_ACCESS_KEY_ID."
  value       = aws_iam_access_key.ci.id
}

output "ci_secret_access_key" {
  description = "GitHub secret AWS_SECRET_ACCESS_KEY. Read with: terraform output -raw ci_secret_access_key"
  value       = aws_iam_access_key.ci.secret
  sensitive   = true
}
