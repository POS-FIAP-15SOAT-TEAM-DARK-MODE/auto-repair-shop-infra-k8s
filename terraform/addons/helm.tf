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

# kube-prometheus-stack — Prometheus + Grafana + node-exporter + kube-state-metrics.
# Collects node/pod CPU & memory and ships pre-built Grafana dashboards for
# them (no manual dashboard authoring needed). Needs no AWS permissions, so it
# runs the same way on restricted (Learner Lab) accounts. Persistence is
# disabled: there is no EBS CSI driver installed here, and Prometheus data
# does not need to survive a pod restart for this use case.
#
# Grafana is exposed via a plain LoadBalancer Service (same mechanism the app
# already uses in Lab mode, no ALB Controller/IRSA needed) so it has a real
# URL instead of requiring kubectl port-forward. Login stays admin/admin —
# acceptable only because this is a short-lived Lab environment for study
# purposes; swap for a generated secret + restricted access before any
# longer-lived deployment.
resource "helm_release" "kube_prometheus_stack" {
  name             = "kube-prometheus-stack"
  repository       = "https://prometheus-community.github.io/helm-charts"
  chart            = "kube-prometheus-stack"
  namespace        = "monitoring"
  create_namespace = true

  # Control-plane component scraping (controller-manager/scheduler/etcd/kube-proxy)
  # is disabled: on managed EKS those endpoints are not reachable, and left on
  # they just show up as permanently failing targets.
  values = [yamlencode({
    alertmanager = { enabled = false }
    prometheus = {
      prometheusSpec = {
        retention = "6h"
        resources = { requests = { cpu = "100m", memory = "256Mi" } }
        # Nil-selector defaults to "only ServiceMonitors labeled release=<this
        # helm release>". Disabled so Prometheus picks up any ServiceMonitor
        # in the cluster (e.g. the app repo's, which doesn't know this
        # release's name) without extra label wiring.
        serviceMonitorSelectorNilUsesHelmValues = false
        podMonitorSelectorNilUsesHelmValues     = false
      }
    }
    grafana = {
      adminUser     = "admin"
      adminPassword = "admin"
      persistence   = { enabled = false }
      resources     = { requests = { cpu = "50m", memory = "128Mi" } }
      service       = { type = "LoadBalancer" }
      # Points at the loki-stack release below (same namespace, so the short
      # service name resolves) for the Explore/logs view.
      additionalDataSources = [{
        name      = "Loki"
        type      = "loki"
        url       = "http://loki-stack:3100"
        access    = "proxy"
        isDefault = false # the chart's own Prometheus datasource is already the default; having two errors Grafana out ("Only one datasource per organization can be marked as default")
      }]
    }
    kubeControllerManager = { enabled = false }
    kubeScheduler         = { enabled = false }
    kubeEtcd              = { enabled = false }
    kubeProxy             = { enabled = false }
  })]
}

# loki-stack — Loki (log storage) + Promtail (DaemonSet shipping container
# stdout from every node). Gives the structured JSON logs (already emitted by
# the app, request_id and all) a queryable home in Grafana's Explore view,
# instead of only kubectl logs. Filesystem storage, no persistence: logs
# don't need to survive a pod restart in this short-lived Lab environment.
resource "helm_release" "loki_stack" {
  name             = "loki-stack"
  repository       = "https://grafana.github.io/helm-charts"
  chart            = "loki-stack"
  namespace        = "monitoring"
  create_namespace = true

  values = [yamlencode({
    loki = {
      persistence = { enabled = false }
      resources   = { requests = { cpu = "50m", memory = "128Mi" } }
    }
    promtail = {
      resources = { requests = { cpu = "50m", memory = "64Mi" } }
    }
    # Grafana already installed by kube-prometheus-stack above.
    grafana = { enabled = false }
  })]
}
