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
