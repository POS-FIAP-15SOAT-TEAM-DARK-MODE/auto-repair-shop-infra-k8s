# The customer-login lambda's function ARN comes from the sibling
# auto-repair-shop-lambda-auth repo's state — same S3 bucket, different key.
# This state never creates or duplicates the lambda itself, only routes to it.
data "terraform_remote_state" "lambda" {
  backend   = "s3"
  workspace = terraform.workspace

  config = {
    bucket = var.state_bucket
    key    = "lambda-auth/terraform.tfstate"
    region = var.region
  }
}
