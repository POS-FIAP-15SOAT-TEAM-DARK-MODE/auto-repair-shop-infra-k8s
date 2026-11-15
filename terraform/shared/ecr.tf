locals {
  tags = {
    Project   = var.project
    ManagedBy = "terraform"
    Scope     = "shared"
  }
}

# Single ECR repo shared by all environments — the same image built once is
# promoted stg -> prd. Lives in `shared` so running the per-env `aws` stack
# twice never collides on the repository name.
resource "aws_ecr_repository" "app" {
  name                 = var.project
  image_tag_mutability = "IMMUTABLE"

  image_scanning_configuration {
    scan_on_push = true
  }

  tags = local.tags
}

resource "aws_ecr_lifecycle_policy" "app" {
  repository = aws_ecr_repository.app.name

  policy = jsonencode({
    rules = [{
      rulePriority = 1
      description  = "Keep only the last 10 images"
      selection = {
        tagStatus   = "any"
        countType   = "imageCountMoreThan"
        countNumber = 10
      }
      action = { type = "expire" }
    }]
  })
}

# One repository per microservice (see docs/fase4 contracts/resources.md). Same
# settings as the gateway repo above: immutable tags, scan on push, keep the
# last 10 images. Pushes use the existing static credentials on Learner Lab;
# with manage_iam = true, the deploy roles' policy (oidc.tf) must list these
# repositories too before their CI can push.
locals {
  service_lifecycle_policy = jsonencode({
    rules = [{
      rulePriority = 1
      description  = "Keep only the last 10 images"
      selection = {
        tagStatus   = "any"
        countType   = "imageCountMoreThan"
        countNumber = 10
      }
      action = { type = "expire" }
    }]
  })
}

resource "aws_ecr_repository" "services" {
  for_each = toset(var.service_repositories)

  name                 = each.key
  image_tag_mutability = "IMMUTABLE"

  image_scanning_configuration {
    scan_on_push = true
  }

  tags = local.tags
}

resource "aws_ecr_lifecycle_policy" "services" {
  for_each = aws_ecr_repository.services

  repository = each.value.name
  policy     = local.service_lifecycle_policy
}
