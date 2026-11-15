# Custom Grafana dashboard for the app's own metrics (API latency,
# service-order volume/status breakdown, notification failures, average time
# per status). Provisioned the same way the chart's own default dashboards
# are: a ConfigMap labeled grafana_dashboard=1, picked up automatically by
# the Grafana sidecar (grafana-sc-dashboard container) — no manual import.
resource "kubernetes_config_map_v1" "app_metrics_dashboard" {
  metadata {
    name      = "auto-repair-shop-app-metrics-dashboard"
    namespace = "monitoring"
    labels = {
      grafana_dashboard = "1"
    }
  }

  data = {
    "app-metrics.json" = file("${path.module}/dashboards/app-metrics.json")
  }

  depends_on = [helm_release.kube_prometheus_stack]
}

# Custom Grafana dashboard for the saga (orchestrated service-order approval):
# started/completed/compensated rates, compensation ratio, step duration p50/p95,
# outbox backlog per service, DLQ (not yet exposed by the services — panel stays
# empty), and Loki log panels to follow one saga_id across services. Same
# provisioning as app-metrics above.
resource "kubernetes_config_map_v1" "saga_dashboard" {
  metadata {
    name      = "auto-repair-shop-saga-dashboard"
    namespace = "monitoring"
    labels = {
      grafana_dashboard = "1"
    }
  }

  data = {
    "saga.json" = file("${path.module}/dashboards/saga.json")
  }

  depends_on = [helm_release.kube_prometheus_stack]
}
