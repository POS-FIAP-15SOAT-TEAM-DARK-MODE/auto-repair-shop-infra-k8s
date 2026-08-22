terraform {
  required_version = ">= 1.10"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
  }

  # Remote state in the bucket created by ../bootstrap. Single (default)
  # workspace — these resources are shared across all environments.
  # `bucket` is intentionally omitted (partial config): the workflows derive it
  # from the AWS account id and pass it via `-backend-config="bucket=..."`.
  backend "s3" {
    key          = "shared/terraform.tfstate"
    region       = "us-east-1"
    encrypt      = true
    use_lockfile = true
  }
}

provider "aws" {
  region = var.region
}
