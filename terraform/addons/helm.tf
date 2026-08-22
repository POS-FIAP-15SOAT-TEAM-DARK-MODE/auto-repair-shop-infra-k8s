# metrics-server — required for the HorizontalPodAutoscaler to read CPU/memory.
resource "helm_release" "metrics_server" {
  name       = "metrics-server"
  repository = "https://kubernetes-sigs.github.io/metrics-server/"
  chart      = "metrics-server"
  namespace  = "kube-system"

  set {
    name  = "args[0]"
    value = "--kubelet-insecure-tls"
  }
}

# AWS Load Balancer Controller — turns the app Ingress into an ALB. Requires
# IRSA, so it is skipped when manage_iam = false (Learner Lab): expose the app
# with a NodePort / `kubectl port-forward` there instead of an ALB Ingress.
resource "helm_release" "alb" {
  count      = var.manage_iam ? 1 : 0
  name       = "aws-load-balancer-controller"
  repository = "https://aws.github.io/eks-charts"
  chart      = "aws-load-balancer-controller"
  namespace  = "kube-system"

  set {
    name  = "clusterName"
    value = data.terraform_remote_state.aws.outputs.cluster_name
  }
  set {
    name  = "region"
    value = var.region
  }
  set {
    name  = "vpcId"
    value = data.terraform_remote_state.aws.outputs.vpc_id
  }
  set {
    name  = "serviceAccount.create"
    value = "true"
  }
  set {
    name  = "serviceAccount.name"
    value = "aws-load-balancer-controller"
  }
  set {
    name  = "serviceAccount.annotations.eks\\.amazonaws\\.com/role-arn"
    value = module.alb_irsa[0].iam_role_arn
  }
}

# External Secrets Operator — syncs Secrets Manager into k8s Secrets. Requires
# IRSA, so it is skipped when manage_iam = false: provide the app's secret as a
# plain Kubernetes Secret there instead of syncing from Secrets Manager.
resource "helm_release" "external_secrets" {
  count            = var.manage_iam ? 1 : 0
  name             = "external-secrets"
  repository       = "https://charts.external-secrets.io"
  chart            = "external-secrets"
  namespace        = "external-secrets"
  create_namespace = true

  set {
    name  = "installCRDs"
    value = "true"
  }
  set {
    name  = "serviceAccount.annotations.eks\\.amazonaws\\.com/role-arn"
    value = module.eso_irsa[0].iam_role_arn
  }
}
