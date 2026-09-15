terraform {
  required_version = ">= 1.10"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
  }

  # bucket passed via -backend-config by the workflow; same bucket as the
  # other states in this repo, different key so they never collide.
  backend "s3" {
    key    = "gateway/terraform.tfstate"
    region = "us-east-1"
  }
}

provider "aws" {
  region = var.region
}
