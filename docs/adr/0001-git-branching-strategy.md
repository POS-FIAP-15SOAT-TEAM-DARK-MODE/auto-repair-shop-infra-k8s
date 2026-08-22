# ADR 0001 — Git branching strategy: feature → develop → main

- Status: Accepted
- Date: 2026-08-22
- Deciders: Giusier F.
- Tags: workflow, ci-cd, governance

## Context

The Tech Challenge Fase 3 brief mandates, for all 4 repositories: a protected `main`/`master` branch with no direct commits, and mandatory Pull Requests for merges. Before this decision, this repo had no branch protection at all.

Like `auto-repair-shop-infra-db`, this repo's Terraform workflow selects `stg`/`prd` via a `workflow_dispatch` input (a Terraform workspace), not by git branch — so `develop` here is a review-staging convention, not a deploy-environment trigger.

## Decision

Adopt the same two-stage flow as the other 3 Tech Challenge repos: feature/fix branches → PR into `develop`; `develop` → PR into `main`. Both branches are GitHub branch-protected: PR required to merge, enforced even for repo admins, no force-push, no branch deletion, 0 required approvals.

## Consequences

### Positive

- Matches the brief's explicit requirement.
- Consistent convention across all 4 Tech Challenge repos.

### Negative

- No functional deploy-environment consequence tied to this branch split (unlike `auto-repair-shop`) — purely procedural here.

## Alternatives considered

- **A. Trunk-based (feature → main directly).** Simpler, but inconsistent with the other repos.

## Notes

- See `auto-repair-shop`'s ADR 0003 for the fuller rationale.
