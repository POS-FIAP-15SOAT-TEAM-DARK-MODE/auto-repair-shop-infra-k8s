output "ecr_repository_url" {
  description = "Push target for CI and image source for the workloads"
  value       = aws_ecr_repository.app.repository_url
}

output "github_oidc_provider_arn" {
  value = one(aws_iam_openid_connect_provider.github[*].arn)
}

output "deploy_role_arns" {
  description = "Map of environment (STG/PRD) -> GitHub Actions deploy role ARN. Empty when manage_iam = false."
  value       = { for e, r in aws_iam_role.deploy : e => r.arn }
}

output "terraform_role_arn" {
  description = "Role the Infra workflow assumes (set as the `infra` env var AWS_TERRAFORM_ROLE_ARN). Null when manage_iam = false."
  value       = one(aws_iam_role.terraform[*].arn)
}
