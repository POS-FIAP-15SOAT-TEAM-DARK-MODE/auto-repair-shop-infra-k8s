# RFC 0001 — API Gateway strategy

- Status: Resolved (see Decision)
- Date: 2026-08-22
- Author: Giusier F.
- Related: issue #5, ADR 0002 (this repo)

## Summary

Issue #5 requires an API Gateway in front of the app and the customer-login lambda, and explicitly calls for a recorded decision between two options: **AWS API Gateway (VPC Link + Lambda integration)** vs. **Kong or Traefik running inside the EKS cluster**. This RFC lays out that decision, plus the two follow-on questions issue #5 also raises: where JWT validation happens, and how rate limiting is applied.

## Problem statement

We need one entry point that:
1. Routes `POST /auth/customer-login` to the lambda in `auto-repair-shop-lambda-auth`.
2. Routes every other request to the main app running in EKS.
3. Leaves public routes (`/ping`, OS status tracking, staff login, the customer-login lambda's own route) reachable without a token, and requires a valid JWT for everything else.
4. Rate-limits the authentication routes specifically.

Constraint that shapes every option below: this project runs on an **AWS Academy Learner Lab** account, which forbids creating new IAM roles or an OIDC provider. The `aws`/`addons`/`shared` Terraform states already auto-detect this (`manage_iam = false`) and degrade accordingly — the ALB Controller add-on, for instance, is skipped entirely under this mode, which is *why* the app is currently exposed via a plain public `LoadBalancer` Service rather than an Ingress.

## Proposal

**Gateway service: AWS API Gateway, HTTP API type.**

**Gateway → app path: public `HTTP_PROXY` integration to the app's existing public ELB.** Not a private VPC Link — a VPC Link requires its own IAM role (blocked under `manage_iam = false`) and typically a dedicated NLB in front of the private backend. Since the app is *already* publicly reachable in this deployment mode (see Constraint above), routing the Gateway straight to that same public hostname adds a real, working entry point without requiring infrastructure this account can't create.

**JWT validation: app-only, no Lambda Authorizer.** The Gateway proxies every route as-is; the app's existing middleware (`internal/app/middleware/auth.go`) does the actual check — already correct (role-based, zero extra DB calls per the project's own `.ai/rules/security.md`). A Lambda Authorizer would duplicate that logic in a second place.

**Rate limiting: native HTTP API stage `route_settings` throttle**, scoped specifically to `POST /auth/customer-login` (5 req/s, burst 10), looser default elsewhere (25 req/s, burst 50).

## Alternatives considered

### A. AWS API Gateway (REST API) + VPC Link

The pattern issue #5 names as the reference option. Private integration, no public hop between Gateway and backend.

- **For:** the textbook "correct" pattern; backend traffic never touches the public internet.
- **Against:** needs a VPC Link IAM role we can't create under `manage_iam = false`, plus typically a dedicated NLB. Not achievable as-is on this account without first solving the broader "no ALB Controller / no IRSA" problem this project already has.
- **Verdict:** the target architecture once account restrictions lift (see Open questions), not viable right now.

### B. Kong or Traefik inside EKS

Run the gateway as another workload in the cluster, instead of a managed AWS service.

- **For:** avoids AWS API Gateway's service limits/cost; keeps everything inside Kubernetes, a single operational model.
- **Against:** means operating a second ingress-controller-class piece of infrastructure ourselves — upgrades, HA, its own plugin ecosystem for JWT/rate-limiting — for a project whose actual traffic and team size don't need that operational weight. Also doesn't fit issue #4's "serverless" framing for the auth path as naturally as a managed API Gateway with native Lambda integration does.
- **Verdict:** rejected — disproportionate operational cost for this project's scale.

### C. HTTP API with a Lambda Authorizer, keeping app-side middleware too

Defense-in-depth: check the JWT at the edge *and* in the app.

- **For:** rejects unauthenticated requests one hop earlier — a protected route hit with no token would 401 at the Gateway layer itself, not just observed as a pass-through from the app.
- **Against:** duplicates JWT-checking logic (claims shape, secret, expiry handling) in two independently-deployed places that must stay in sync. No realistic threat model in this project that app-only validation doesn't already cover — a request with no token still ends up 401 either way, since the app already returns that correctly and the Gateway just proxies the response through unchanged.
- **Verdict:** rejected for now; the Notes below flag when this should be revisited.

## Open questions / risks

- **If this account's IAM restrictions ever lift** (a real AWS account instead of a Learner Lab, or a future account with `manage_iam = true` fully working end-to-end including the ALB Controller), the public-HTTP-proxy choice should be revisited — a private VPC Link becomes straightforwardly achievable, and the "the app is already public anyway" justification stops applying once there's a genuinely private backend to protect.
- **A Lambda Authorizer becomes worth reconsidering** if a second, independent client of these APIs is ever added that shouldn't be trusted to correctly enforce its own auth checks the way the current single app does — edge validation is a stronger guarantee for that scenario than "we assume the one backend behaves."
- Rate limiting is configured but not load-tested against real traffic; the 5 req/s figure is a reasonable starting default, not a value derived from measured usage patterns.

## Decision

Recorded as `docs/adr/0002-api-gateway-topology.md` in this repo. Implementation: `terraform/gateway/`.
