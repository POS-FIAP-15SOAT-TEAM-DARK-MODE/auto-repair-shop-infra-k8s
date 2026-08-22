output "grafana_admin_password" {
  description = "Grafana 'admin' password (kube-prometheus-stack). Retrieve with: terraform output -raw grafana_admin_password"
  value       = random_password.grafana_admin.result
  sensitive   = true
}
