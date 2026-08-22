variable "region" {
  description = "AWS region"
  type        = string
  default     = "us-east-1"
}

variable "project" {
  description = "Project name, used as a resource prefix"
  type        = string
  default     = "auto-repair-shop"
}

variable "state_bucket" {
  description = "S3 bucket holding the remote state (used to read the shared stack). Passed by the workflows, derived from the AWS account id."
  type        = string
}

variable "manage_iam" {
  description = "Let Terraform create the EKS cluster/node IAM roles and IRSA OIDC provider. Set to false on restricted accounts (Learner Lab): the cluster and node group then reuse execution_role_arn and IRSA is disabled."
  type        = bool
  default     = true
}

variable "execution_role_arn" {
  description = "Pre-existing IAM role passed to the EKS cluster and node group when manage_iam = false (e.g. the Learner Lab `LabRole`)."
  type        = string
  default     = ""
}

# --- Network ---
variable "vpc_cidr" {
  description = "CIDR block for the VPC"
  type        = string
  default     = "10.0.0.0/16"
}

# --- EKS ---
variable "kubernetes_version" {
  description = "EKS control plane version"
  type        = string
  default     = "1.31"
}
