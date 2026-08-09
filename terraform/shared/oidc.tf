# Everything in this file is IAM and is skipped when manage_iam = false
# (restricted accounts such as AWS Academy Learner Lab). In that mode the shared
# stack creates only the ECR repo and the workflows use static credentials.

# GitHub Actions OIDC provider — lets workflows assume IAM roles without any
# long-lived access keys stored as secrets.
resource "aws_iam_openid_connect_provider" "github" {
  count          = var.manage_iam ? 1 : 0
  url            = "https://token.actions.githubusercontent.com"
  client_id_list = ["sts.amazonaws.com"]
  # thumbprint_list is optional for this well-known IdP with AWS provider v6.
}

locals {
  environments = var.manage_iam ? toset(var.environments) : toset([])
}

data "aws_iam_policy_document" "deploy_assume" {
  for_each = local.environments

  statement {
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [aws_iam_openid_connect_provider.github[0].arn]
    }

    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:aud"
      values   = ["sts.amazonaws.com"]
    }

    # Only the matching GitHub Environment (STG/PRD) may assume this role.
    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:sub"
      values   = ["repo:${var.github_repo}:environment:${each.key}"]
    }
  }
}

resource "aws_iam_role" "deploy" {
  for_each           = local.environments
  name               = "${var.project}-deploy-${lower(each.key)}"
  assume_role_policy = data.aws_iam_policy_document.deploy_assume[each.key].json
  tags               = local.tags
}

# Push to ECR and read the EKS cluster for kubeconfig. Kubernetes RBAC itself
# comes from the EKS access entry created in the `aws` stack.
data "aws_iam_policy_document" "deploy_permissions" {
  statement {
    sid       = "EcrAuth"
    actions   = ["ecr:GetAuthorizationToken"]
    resources = ["*"]
  }

  statement {
    sid = "EcrPushPull"
    actions = [
      "ecr:BatchCheckLayerAvailability",
      "ecr:CompleteLayerUpload",
      "ecr:InitiateLayerUpload",
      "ecr:PutImage",
      "ecr:UploadLayerPart",
      "ecr:BatchGetImage",
      "ecr:GetDownloadUrlForLayer",
    ]
    resources = [aws_ecr_repository.app.arn]
  }

  statement {
    sid       = "EksDescribe"
    actions   = ["eks:DescribeCluster"]
    resources = ["*"]
  }
}

resource "aws_iam_role_policy" "deploy" {
  for_each = local.environments
  name     = "deploy"
  role     = aws_iam_role.deploy[each.key].id
  policy   = data.aws_iam_policy_document.deploy_permissions.json
}

# Broad role the Infra (Terraform) workflow assumes — via the `infra` GitHub
# Environment — to run the shared/aws/addons states. AdministratorAccess keeps
# this simple for a study project; scope it down for real use.
data "aws_iam_policy_document" "terraform_assume" {
  count = var.manage_iam ? 1 : 0

  statement {
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [aws_iam_openid_connect_provider.github[0].arn]
    }

    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:aud"
      values   = ["sts.amazonaws.com"]
    }

    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:sub"
      values   = ["repo:${var.github_repo}:environment:infra"]
    }
  }
}

resource "aws_iam_role" "terraform" {
  count              = var.manage_iam ? 1 : 0
  name               = "${var.project}-terraform"
  assume_role_policy = data.aws_iam_policy_document.terraform_assume[0].json
  tags               = local.tags
}

resource "aws_iam_role_policy_attachment" "terraform_admin" {
  count      = var.manage_iam ? 1 : 0
  role       = aws_iam_role.terraform[0].name
  policy_arn = "arn:aws:iam::aws:policy/AdministratorAccess"
}
