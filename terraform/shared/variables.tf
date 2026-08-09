variable "region" {
  type    = string
  default = "us-east-1"
}

variable "project" {
  type    = string
  default = "auto-repair-shop"
}

variable "github_repo" {
  description = "owner/repo allowed to assume the deploy roles via OIDC"
  type        = string
  default     = "POS-FIAP-15SOAT-TEAM-DARK-MODE/auto-repair-shop"
}

variable "environments" {
  description = "GitHub Actions environments that each get a deploy role"
  type        = list(string)
  default     = ["STG", "PRD"]
}

variable "manage_iam" {
  description = "Create the GitHub OIDC provider and the terraform/deploy IAM roles. Set to false on restricted accounts (e.g. AWS Academy Learner Lab) that forbid IAM writes — only the ECR repo is then created and the workflows must authenticate with static credentials."
  type        = bool
  default     = true
}
