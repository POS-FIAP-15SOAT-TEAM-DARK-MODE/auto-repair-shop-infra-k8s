output "environment" {
  value = local.environment
}

output "region" {
  value = var.region
}

output "cluster_name" {
  value = local.cluster_name
}

output "cluster_endpoint" {
  value = local.cluster_endpoint
}

output "vpc_id" {
  value = module.vpc.vpc_id
}

output "private_subnets" {
  description = "Private subnet ids, consumed by the sibling auto-repair-shop-infra-db repo (RDS placement) via terraform_remote_state."
  value       = module.vpc.private_subnets
}

output "node_security_group_id" {
  description = "EKS node security group id, consumed by the sibling auto-repair-shop-infra-db repo to scope the RDS security group ingress to cluster nodes only."
  value       = local.node_security_group_id
}

output "oidc_provider_arn" {
  description = "Cluster OIDC provider ARN, for IRSA in the addons state. Empty when manage_iam = false."
  value       = local.oidc_provider_arn
}

output "configure_kubectl" {
  description = "Point kubectl at this cluster"
  value       = "aws eks update-kubeconfig --region ${var.region} --name ${local.cluster_name}"
}
