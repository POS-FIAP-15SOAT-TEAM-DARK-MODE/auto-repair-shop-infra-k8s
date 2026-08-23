# ADR 0002 — Cluster observability add-ons: kube-prometheus-stack + loki-stack

- Status: Accepted
- Date: 2026-08-23
- Deciders: Auto Repair Shop Team
- Tags: observability, monitoring, logs, security, tech-challenge

## Context

See the sibling ADR in `auto-repair-shop`
(`0004-observability-stack-self-hosted-prometheus-grafana-loki.md`) for why a
self-hosted stack was chosen over Datadog/New Relic. This ADR covers the
infra-side implementation decisions specific to this repo: how the add-ons
are wired into the `addons` Terraform state, and the trade-offs of running
them on a restricted, short-lived AWS Academy Learner Lab account.

## Decision

1. **kube-prometheus-stack** (Prometheus + Grafana + node-exporter +
   kube-state-metrics) installed via `helm_release` in `terraform/addons/`.
   Alertmanager and control-plane component scraping
   (`kubeControllerManager`/`kubeScheduler`/`kubeEtcd`/`kubeProxy`) are
   disabled: alerting was not part of this requirement, and managed EKS does
   not expose those control-plane endpoints — leaving them on just produces
   permanently-failing scrape targets.
2. **Grafana is exposed via a plain `LoadBalancer` Service**, not an Ingress
   (the ALB Controller needs IRSA, unavailable when `manage_iam = false` on
   Learner Lab) and not `kubectl port-forward` (impractical for more than one
   person to use during a live demo/study session). Login stays the fixed
   `admin`/`admin` set directly in the Helm values.
3. **`serviceMonitorSelectorNilUsesHelmValues` /
   `podMonitorSelectorNilUsesHelmValues` set to `false`** on the Prometheus
   spec, so Prometheus watches *every* `ServiceMonitor`/`PodMonitor` in the
   cluster. The chart's default (`true`) restricts discovery to resources
   labeled `release: kube-prometheus-stack` — the app repo's own
   `ServiceMonitor` has no reason to know this Helm release's name, and
   requiring that label would couple the two repos unnecessarily.
4. **loki-stack** (Loki + Promtail) installed as a second `helm_release`,
   with `grafana.enabled = false` (reusing the Grafana from #1) and wired as
   an `additionalDataSources` entry on that Grafana pointing at
   `http://loki-stack:3100`.
5. Both new releases run with `persistence.enabled = false` — no EBS CSI
   driver is installed in this cluster, and neither metrics history nor log
   history needs to survive a pod restart for this use case.
6. A custom Grafana dashboard ("Auto Repair Shop — App Metrics") is
   provisioned as a `kubernetes_config_map_v1` labeled `grafana_dashboard: "1"`
   (`terraform/addons/dashboards.tf`), the same discovery mechanism the
   chart uses for its own built-in dashboards — no manual import step.

## Consequences

### Positive

- One Grafana serves both infra dashboards (chart defaults: cluster/node
  CPU) and the app's own custom dashboard — a single pane of glass, one URL,
  one login.
- No IRSA/IAM dependency anywhere in this ADR: everything here runs
  identically whether `manage_iam` is `true` or `false`, unlike the ALB
  Controller and External Secrets add-ons.
- Opening the ServiceMonitor selector cluster-wide means any future service
  in any namespace gets scraped automatically by just shipping a
  `ServiceMonitor` alongside it — no coordination with this repo required.

### Negative

- **Grafana is reachable from the public internet with a static, well-known
  password (`admin`/`admin`) and no TLS.** This is only acceptable because
  the Lab account is short-lived and used for study/demo purposes; it must
  not be repeated as-is for anything longer-lived. The fix (generated
  secret, IP allowlist on the LoadBalancer security group, or reverting to
  `port-forward`-only) is a small, isolated change to
  `terraform/addons/helm.tf` when needed.
- Opening `serviceMonitorSelectorNilUsesHelmValues` to `false` means
  Prometheus will also pick up any accidental or malicious `ServiceMonitor`
  created by anyone with cluster access — an acceptable risk on a
  single-team Lab account, not on a shared/multi-tenant cluster.
- No metrics/log retention beyond the pod's lifetime (see the app-side ADR).

## Alternatives considered

- **A. AWS Managed Grafana + Amazon Managed Prometheus (AMP).** True
  managed service with IAM-based auth instead of a shared password —
  strictly better security posture. Rejected for this Lab account: cost and
  service-availability are uncertain on AWS Academy accounts, and it adds a
  second AWS console dependency beyond what this challenge needs to
  demonstrate.
- **B. CloudWatch Container Insights** instead of Prometheus/Grafana
  entirely. Native, IAM-authenticated, no extra Helm release — but weaker
  custom-metric/dashboard ergonomics for the app-specific panels this
  challenge asks for, and doesn't solve the logs-with-correlation
  requirement on its own. Considered and rejected during this same
  conversation before landing on Prometheus/Grafana + Loki.
- **C. Keep Grafana on `kubectl port-forward` only** (the original
  implementation). Safer (nothing public), but unusable for more than one
  person to review during the video demo or a live walkthrough — the
  concrete reason this ADR moved to `LoadBalancer`.

## Notes

- If this cluster's lifetime is extended beyond the tech-challenge
  submission, revisit the Grafana credential/exposure decision (#2) first —
  it is the one item here that is explicitly a short-term trade-off, not a
  permanent architectural choice.
