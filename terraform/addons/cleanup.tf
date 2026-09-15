# Terraform only knows about the LoadBalancer Services it created itself
# (Grafana). The app's own Service (kubectl-applied by auto-repair-shop's
# docker.yml, entirely outside this state) is invisible to Terraform — so a
# `terraform destroy` on the `aws` layer has no idea its backing ELB exists,
# and doesn't wait for it. The orphaned ELB's ENIs stay attached to the
# public subnets, which then hang "Still destroying..." forever (AWS refuses
# to delete a subnet/Internet Gateway with an ENI still in it).
#
# Fix: on destroy, before the `aws` layer's VPC teardown ever runs, delete
# every LoadBalancer-type Service in the cluster (not just ones this state
# manages) and wait for kubectl to confirm they're gone — draining the
# in-cluster resource is what actually triggers AWS to deprovision the ELB.
# `|| true` everywhere: this is best-effort cleanup, not a hard dependency —
# a failure here (e.g. cluster already half-gone) must never block the rest
# of destroy.
resource "null_resource" "cleanup_loadbalancer_services" {
  triggers = {
    cluster_name = data.terraform_remote_state.aws.outputs.cluster_name
    region       = var.region
  }

  provisioner "local-exec" {
    when    = destroy
    command = <<-EOT
      aws eks update-kubeconfig --region ${self.triggers.region} --name ${self.triggers.cluster_name} || true
      kubectl delete svc --all-namespaces --field-selector spec.type=LoadBalancer --wait=true --timeout=180s || true
    EOT
  }
}
