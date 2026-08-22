locals {
  # The environment comes from the Terraform workspace. "default" maps to stg so
  # `validate` / `plan` work before you select a workspace.
  #   terraform workspace new stg   (or: terraform workspace select stg)
  environment = terraform.workspace == "default" ? "stg" : terraform.workspace

  name = "${var.project}-${local.environment}"

  tags = {
    Project     = var.project
    Environment = local.environment
    ManagedBy   = "terraform"
  }

  # Two AZs is enough for EKS (and for RDS, provisioned by the sibling
  # auto-repair-shop-infra-db repo) and keeps the plan cheap.
  azs = slice(data.aws_availability_zones.available.names, 0, 2)

  # Per-environment sizing. prd is bigger and more resilient.
  env_config = {
    stg = {
      node_types   = ["t3.medium"]
      node_desired = 2
      node_min     = 1
      node_max     = 3
    }
    prd = {
      node_types   = ["t3.large"]
      node_desired = 3
      node_min     = 2
      node_max     = 6
    }
  }

  cfg = local.env_config[local.environment]
}
