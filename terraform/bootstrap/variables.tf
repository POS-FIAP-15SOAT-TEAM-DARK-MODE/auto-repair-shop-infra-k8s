variable "region" {
  type    = string
  default = "us-east-1"
}

variable "state_bucket_name" {
  description = "Globally-unique S3 bucket name for Terraform remote state. The workflows derive it from the AWS account id (auto-repair-shop-tfstate-<account_id>) so it never collides globally and adapts to ephemeral lab accounts."
  type        = string
}
