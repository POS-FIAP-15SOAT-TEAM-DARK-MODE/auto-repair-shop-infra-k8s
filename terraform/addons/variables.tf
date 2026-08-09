variable "region" {
  type    = string
  default = "us-east-1"
}

variable "project" {
  type    = string
  default = "auto-repair-shop"
}

variable "state_bucket" {
  description = "S3 bucket holding the remote state (used to read the aws stack). Passed by the workflows, derived from the AWS account id."
  type        = string
}

variable "manage_iam" {
  description = "Install the IRSA-based add-ons (ALB Controller, External Secrets). Requires the cluster IRSA OIDC provider, so it must match the aws stack. On restricted accounts (Learner Lab) set false: only metrics-server is installed."
  type        = bool
  default     = true
}
