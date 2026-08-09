# Pull the GitHub Actions deploy role ARNs from the shared stack. Only needed
# when manage_iam = true; on restricted accounts there is no deploy role and the
# cluster creator (enable_cluster_creator_admin_permissions) already has access.
data "terraform_remote_state" "shared" {
  count   = var.manage_iam ? 1 : 0
  backend = "s3"
  config = {
    bucket = var.state_bucket
    key    = "shared/terraform.tfstate"
    region = var.region
  }
}

locals {
  deploy_role_arn = var.manage_iam ? data.terraform_remote_state.shared[0].outputs.deploy_role_arns[upper(local.environment)] : null
}

# Grant this environment's deploy role edit access to this cluster, so the
# pipeline can `kubectl apply` after `aws eks update-kubeconfig`.
resource "aws_eks_access_entry" "deploy" {
  count         = var.manage_iam ? 1 : 0
  cluster_name  = local.cluster_name
  principal_arn = local.deploy_role_arn
  type          = "STANDARD"
}

resource "aws_eks_access_policy_association" "deploy" {
  count         = var.manage_iam ? 1 : 0
  cluster_name  = local.cluster_name
  principal_arn = local.deploy_role_arn
  policy_arn    = "arn:aws:eks::aws:cluster-access-policy/AmazonEKSEditPolicy"

  access_scope {
    type = "cluster"
  }
}
