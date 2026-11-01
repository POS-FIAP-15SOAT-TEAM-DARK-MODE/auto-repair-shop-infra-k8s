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

variable "aws_endpoint" {
  description = "Override endpoint for SNS and SQS (e.g. http://localhost:4566 for MiniStack). Leave null on AWS."
  type        = string
  default     = null
}

variable "state_bucket" {
  description = "S3 bucket holding the remote state. Passed by the workflows (unused by this state, kept for the common -var list)."
  type        = string
  default     = null
}

variable "manage_iam" {
  description = "Passed by the workflows to every layer. This state creates no IAM, so the value is unused."
  type        = bool
  default     = true
}
