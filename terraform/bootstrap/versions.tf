terraform {
  required_version = ">= 1.10"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
  }
}

# Bootstrap uses LOCAL state — it creates the S3 bucket that the `shared` and
# `aws` stacks then use as their remote backend. Run once.
provider "aws" {
  region = var.region
}
