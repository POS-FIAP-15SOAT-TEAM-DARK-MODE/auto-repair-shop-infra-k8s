# ADR 0003 — Read the app's backend hostname from SSM, not a manual variable

- Status: Accepted
- Date: 2026-08-22
- Deciders: Giusier F.
- Tags: infra, api-gateway, cross-repo, terraform

## Context

The `gateway` state's `HTTP_PROXY` integration (see ADR 0002) needs the app's public ELB hostname. That ELB is created by Kubernetes' in-tree AWS provider from a `LoadBalancer` Service in `auto-repair-shop`, not by any Terraform `apply` — so unlike `db_host` or `function_arn`, there's no `terraform_remote_state` output anywhere to read it from.

The first working version of this gateway used a manually-set GitHub repo variable (`APP_BACKEND_HOST`), copy-pasted from a deploy run's summary. This worked but goes stale silently on every ELB recreation, with nothing forcing a human to notice and update it.

## Decision

`gateway.tf` reads the hostname via an `aws_ssm_parameter` data source at `/auto-repair-shop/<env>/app-backend-host`. `auto-repair-shop`'s `docker.yml` deploy job writes that parameter as the last step of every deploy (see that repo's ADR 0004 for the full rationale on the producing side).

## Consequences

### Positive

- No manual variable to remember to update; every app redeploy keeps the parameter current automatically.
- Re-running `terraform apply` on this state after any app redeploy picks up a new hostname with no code change.

### Negative

- Adds a real *deploy-order* dependency: this state's very first `apply` will fail with a "parameter not found" error until the app has deployed at least once. Documented in this repo's README `Deploy` section, not enforced by tooling (Terraform can't express "wait for an external system's first successful run" as a dependency).
- Reading external system state (SSM) at `plan`/`apply` time means this state's plan is not fully deterministic from its own Terraform sources alone — a `plan` today and a `plan` tomorrow can differ even with zero code changes, if the app has redeployed in between.

## Alternatives considered

See `auto-repair-shop`'s ADR 0004 — the alternatives (manual variable, NLB + tag-based `data "aws_lb"` lookup, Terraform-managed Kubernetes Service) were evaluated together with the producing side, since the decision spans both repos.

## Notes

- Companion decision, `auto-repair-shop` ADR 0004.
