# IRSA roles for the add-ons that need AWS permissions. Skipped entirely when
# manage_iam = false (Learner Lab): those accounts cannot create IAM roles, and
# there is no cluster IRSA OIDC provider to bind them to.

# AWS Load Balancer Controller — provisions the ALB behind the app Ingress.
module "alb_irsa" {
  count   = var.manage_iam ? 1 : 0
  source  = "terraform-aws-modules/iam/aws//modules/iam-role-for-service-accounts-eks"
  version = "~> 5.0"

  role_name                              = "${local.name}-alb-controller"
  attach_load_balancer_controller_policy = true

  oidc_providers = {
    main = {
      provider_arn               = data.terraform_remote_state.aws.outputs.oidc_provider_arn
      namespace_service_accounts = ["kube-system:aws-load-balancer-controller"]
    }
  }
}

# External Secrets Operator — reads this environment's app secret from Secrets Manager.
module "eso_irsa" {
  count   = var.manage_iam ? 1 : 0
  source  = "terraform-aws-modules/iam/aws//modules/iam-role-for-service-accounts-eks"
  version = "~> 5.0"

  role_name                      = "${local.name}-external-secrets"
  attach_external_secrets_policy = true

  external_secrets_secrets_manager_arns = [
    "arn:aws:secretsmanager:${var.region}:*:secret:${local.name}/app*",
  ]

  oidc_providers = {
    main = {
      provider_arn               = data.terraform_remote_state.aws.outputs.oidc_provider_arn
      namespace_service_accounts = ["external-secrets:external-secrets"]
    }
  }
}
