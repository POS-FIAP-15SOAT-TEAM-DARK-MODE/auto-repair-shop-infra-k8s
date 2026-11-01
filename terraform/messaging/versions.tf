terraform {
  required_version = ">= 1.10"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
  }

  # Remote state in the bucket created by ../bootstrap. Workspaces stg/prd, as
  # in the other per-environment states. `bucket` is a partial config: the
  # workflow passes it via `-backend-config="bucket=..."`.
  backend "s3" {
    key          = "messaging/terraform.tfstate"
    region       = "us-east-1"
    encrypt      = true
    use_lockfile = true
  }
}

# When aws_endpoint is set (MiniStack in CI), point SNS/SQS at it and skip the
# calls that need a real AWS account. Credentials come from the environment.
provider "aws" {
  region = var.region

  skip_credentials_validation = var.aws_endpoint != null
  skip_metadata_api_check     = var.aws_endpoint != null
  skip_requesting_account_id  = var.aws_endpoint != null

  dynamic "endpoints" {
    for_each = var.aws_endpoint == null ? [] : [var.aws_endpoint]
    content {
      sns = endpoints.value
      sqs = endpoints.value
    }
  }
}
