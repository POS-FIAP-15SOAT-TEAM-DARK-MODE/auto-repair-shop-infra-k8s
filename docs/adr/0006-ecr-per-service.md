# ADR 0006 — One ECR repository per microservice

- Status: Accepted
- Date: 2026-11-01
- Deciders: Auto Repair Shop Team
- Tags: containers, ecr, ci, tech-challenge

## Context

The monolith is built and pushed to a single ECR repository (`auto-repair-shop`,
`aws_ecr_repository.app`). Phase 4 splits the application into six services
(customer, catalog, billing, execution, history, service order), plus the
gateway that keeps the existing repository. Each service has its own repository
and its own CI pipeline, so they need separate push targets.

## Decision

1. **One ECR repository per microservice**, named after the repo of the service
   (for example `auto-repair-shop-billing-service`), created in the `shared`
   state with `for_each` over `var.service_repositories`.
2. **Same settings as the gateway repository**: `IMMUTABLE` tags,
   `scan_on_push = true`, and a lifecycle policy that keeps the last 10 images.
3. **The gateway repository is not changed.** `aws_ecr_repository.app` and its
   lifecycle policy stay as they are, so the existing images and the deploy
   role's references keep working.
4. **Output `service_repository_urls`** maps each repository name to its URL, so
   service pipelines can read the push target without hard-coding account IDs.
5. **Shared state, not per environment.** As with the gateway repository, images
   are built once and promoted between `stg` and `prd`, so the repositories
   belong to the `shared` state.

## Consequences

### Positive

- Each service can be scanned, tagged and rolled back on its own.
- Immutable tags keep a tag pointing at the same image for the life of the
  repository.
- Lifecycle policies bound storage cost per service.

### Negative

- With `manage_iam = true`, the deploy role's ECR permissions in
  `terraform/shared/oidc.tf` allow only the gateway repository. Each service's
  deploy role or policy must be extended before its CI can push. This is not
  changed in this ADR, because it needs the service repository names and the
  trust conditions to be settled first.
- Six more repositories to inspect and clean up when the environment is torn
  down.

## Alternatives considered

- **A. One repository with a tag per service** (`<service>-<sha>`). Fewer
  resources, but a single lifecycle policy would expire images of one service
  because of pushes from another, and the scan and permission boundaries would
  be shared. Rejected.
- **B. Repositories per environment.** Would break the build-once, promote
  model already in use for the gateway. Rejected.
- **C. Create the repositories in each service's own repo.** Repository
  lifecycle would then depend on each service's pipeline, and the shared
  Terraform would lose control of the names. Rejected.
