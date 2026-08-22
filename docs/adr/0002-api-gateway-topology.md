# ADR 0002 — API Gateway topology: HTTP API, public proxy to the app, JWT validation stays app-only

- Status: Accepted
- Date: 2026-08-22
- Deciders: Giusier F.
- Tags: api-gateway, security, jwt, infra
- Related: Fase 3 issue #5

## Context

Issue #5 asks for an API Gateway in front of the app and the customer-login lambda (`auto-repair-shop-lambda-auth`, issue #4), with public routes exempt from JWT, everything else protected, and an explicit decision to record: **AWS API Gateway (VPC Link + Lambda integration) vs. Kong/Traefik inside EKS**. It also asks whether JWT validation happens at the Gateway (an Authorizer) or only in the app, and requires rate limiting on the authentication routes.

Three sub-decisions had to be made, all constrained by the same fact: this project runs on an **AWS Academy Learner Lab** account, which forbids creating new IAM roles/OIDC providers (`manage_iam = false`, established in the `aws`/`addons`/`shared` states). The app is exposed in this mode via a plain Kubernetes `LoadBalancer` Service (a public Classic ELB) rather than an Ingress + ALB Controller, since the ALB Controller add-on itself is skipped under Lab restrictions (no IRSA).

## Decision

1. **Gateway type: AWS API Gateway, HTTP API** (not REST API, not Kong/Traefik). Cheaper than REST API, has native Lambda proxy integration, and doesn't require running/operating a second in-cluster ingress layer the way Kong/Traefik would.
2. **Gateway → app path: public HTTP_PROXY integration to the app's existing public ELB — not a private VPC Link.** A VPC Link needs a dedicated NLB plus an IAM role for the link itself; both are either extra infrastructure or outright blocked under `manage_iam = false`. Since the app is already publicly reachable in this deployment mode anyway (see context), routing the Gateway's `HTTP_PROXY` integration straight to that same public hostname adds a real entry point without adding IAM surface area we can't create.
3. **JWT validation stays app-only — no Lambda Authorizer.** The Gateway is a plain proxy for every route, public and protected alike. The app's existing auth middleware (`internal/app/middleware/auth.go` in `auto-repair-shop`) already does this correctly — parses the `Authorization` header, checks roles, makes zero extra DB calls — so a Lambda Authorizer would duplicate that logic in a second place that has to be kept in sync, for no functional gain.
4. **Rate limiting:** the Gateway stage's native `route_settings` throttle, scoped specifically to `POST /auth/customer-login` (5 req/s, burst 10), tighter than the default (25 req/s, burst 50) applied to every other route.

## Consequences

### Positive

- No new IAM roles required anywhere in this state — works cleanly under Learner Lab's restrictions with zero special-casing.
- Single source of truth for JWT validation (the app), avoiding two auth implementations that could drift.
- HTTP API's native per-route throttle satisfies the rate-limiting requirement with no extra component.

### Negative

- **Public HTTP proxy is not the "correct" production-grade pattern** a private VPC Link would be — traffic between the Gateway and the app's backend traverses the public internet rather than staying inside the VPC. Acceptable here because the backend (the app's ELB) is *already* public in this deployment mode for an unrelated reason (no ALB Controller); a genuinely private backend would make this tradeoff much less acceptable and should force a VPC Link (or an ALB Controller migration) instead.
- Every request incurs one extra network hop that adds no defense-in-depth (Gateway → public ELB → cluster), versus a design where the Gateway is the *only* public entry point.
- If `manage_iam` ever flips to `true` (a real AWS account, not a Lab), this decision should be revisited — a VPC Link becomes straightforwardly achievable at that point, and the "already public anyway" justification no longer applies once the ALB Controller/Ingress path is available.

## Alternatives considered

- **A. AWS API Gateway (REST API) + VPC Link.** The "textbook" private-integration pattern. Rejected for now due to the IAM-role and extra-NLB cost under Lab restrictions — not rejected as a target architecture, just as this project's current deployment mode.
- **B. Kong or Traefik inside EKS.** Avoids AWS Gateway service limits/cost, but means operating a second ingress-controller-class workload ourselves (upgrades, HA, its own auth-plugin ecosystem) instead of using a managed service — disproportionate operational cost for what this project needs, and doesn't naturally fit "serverless Lambda in front" from issue #4's framing.
- **C. Lambda Authorizer at the Gateway, keeping app-side middleware too (defense in depth).** Considered and rejected: doubles the maintenance surface for JWT logic with no realistic threat model in this project that the app-only check doesn't already cover.

## Notes

- The app's public hostname isn't a Terraform-managed resource (see `auto-repair-shop`'s ADR 0004) — this state reads it via an SSM Parameter Store data source, documented separately in ADR 0003 of this repo.
- Two real bugs were hit and fixed while implementing this: a stage/route creation race (missing `depends_on`, since `route_settings.route_key` is a plain string Terraform can't infer a dependency from) and a malformed `aws_lambda_permission.source_arn` (route_key's space-separated `"METHOD path"` syntax isn't valid inside an execute-api ARN, which needs `METHOD/path`). Both are documented inline in `gateway.tf` at the resources they affected.
