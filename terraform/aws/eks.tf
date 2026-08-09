# Full account: the upstream module manages the cluster, node IAM roles and the
# IRSA OIDC provider.
module "eks" {
  count   = var.manage_iam ? 1 : 0
  source  = "terraform-aws-modules/eks/aws"
  version = "~> 21.0"

  name               = "${local.name}-eks"
  kubernetes_version = var.kubernetes_version

  endpoint_public_access = true

  # API auth mode + let the state's caller manage the cluster; deploy roles are
  # granted access via aws_eks_access_entry (access.tf).
  enable_cluster_creator_admin_permissions = true

  vpc_id     = module.vpc.vpc_id
  subnet_ids = module.vpc.private_subnets

  eks_managed_node_groups = {
    default = {
      instance_types = local.cfg.node_types
      desired_size   = local.cfg.node_desired
      min_size       = local.cfg.node_min
      max_size       = local.cfg.node_max
    }
  }

  tags = local.tags
}

# Restricted accounts (manage_iam = false, e.g. AWS Academy Learner Lab): the
# module is unusable — it always calls iam:GetRole on the caller, which the lab
# denies — so create the cluster and node group directly, reusing an existing
# role (execution_role_arn) for both the control plane and the nodes. No IAM and
# no IRSA OIDC provider are created here.
resource "aws_eks_cluster" "lab" {
  count    = var.manage_iam ? 0 : 1
  name     = "${local.name}-eks"
  role_arn = var.execution_role_arn
  version  = var.kubernetes_version

  vpc_config {
    subnet_ids              = module.vpc.private_subnets
    endpoint_public_access  = true
    endpoint_private_access = true
  }

  # Grant the creating identity cluster-admin without an iam:GetRole lookup, so
  # kubectl works without any managed IAM.
  access_config {
    authentication_mode                         = "API"
    bootstrap_cluster_creator_admin_permissions = true
  }

  tags = local.tags
}

resource "aws_eks_node_group" "lab" {
  count           = var.manage_iam ? 0 : 1
  cluster_name    = aws_eks_cluster.lab[0].name
  node_group_name = "default"
  node_role_arn   = var.execution_role_arn
  subnet_ids      = module.vpc.private_subnets
  instance_types  = local.cfg.node_types

  scaling_config {
    desired_size = local.cfg.node_desired
    min_size     = local.cfg.node_min
    max_size     = local.cfg.node_max
  }

  tags = local.tags
}

# Abstract the cluster attributes so the rest of the state does not branch on
# which implementation created it.
locals {
  cluster_name           = var.manage_iam ? module.eks[0].cluster_name : aws_eks_cluster.lab[0].name
  cluster_endpoint       = var.manage_iam ? module.eks[0].cluster_endpoint : aws_eks_cluster.lab[0].endpoint
  oidc_provider_arn      = var.manage_iam ? module.eks[0].oidc_provider_arn : ""
  node_security_group_id = var.manage_iam ? module.eks[0].node_security_group_id : aws_eks_cluster.lab[0].vpc_config[0].cluster_security_group_id
}
