locals {
  environment = terraform.workspace == "default" ? "stg" : terraform.workspace
  name        = "${var.project}-${local.environment}"
}

# Reads the per-environment `aws` state (same workspace).
data "terraform_remote_state" "aws" {
  backend   = "s3"
  workspace = terraform.workspace

  config = {
    bucket = var.state_bucket
    key    = "aws/terraform.tfstate"
    region = var.region
  }
}

data "aws_eks_cluster" "this" {
  name = data.terraform_remote_state.aws.outputs.cluster_name
}

data "aws_eks_cluster_auth" "this" {
  name = data.terraform_remote_state.aws.outputs.cluster_name
}
