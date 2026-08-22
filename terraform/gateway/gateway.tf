locals {
  environment = terraform.workspace == "default" ? "stg" : terraform.workspace
  name        = "${var.project}-${local.environment}-gateway"

  # Route key for the customer-login endpoint, referenced by both the route
  # itself and its throttle override below — kept as a local so they can't
  # drift apart.
  auth_route_key = "POST /auth/customer-login"

  tags = {
    Project     = var.project
    Environment = local.environment
    ManagedBy   = "terraform"
  }
}

resource "aws_apigatewayv2_api" "main" {
  name          = local.name
  protocol_type = "HTTP"
  tags          = local.tags
}

# --- Route 1: customer-login -> the lambda (issue #4) ---

resource "aws_apigatewayv2_integration" "lambda_login" {
  api_id                 = aws_apigatewayv2_api.main.id
  integration_type       = "AWS_PROXY"
  integration_uri        = data.terraform_remote_state.lambda.outputs.function_arn
  payload_format_version = "2.0"
}

resource "aws_apigatewayv2_route" "customer_login" {
  api_id    = aws_apigatewayv2_api.main.id
  route_key = local.auth_route_key
  target    = "integrations/${aws_apigatewayv2_integration.lambda_login.id}"
}

# API Gateway needs explicit permission to invoke the lambda — a
# resource-based policy on the function, not an IAM role, so this works
# under Learner Lab's manage_iam=false restriction with no changes needed.
resource "aws_lambda_permission" "apigw_invoke_login" {
  statement_id  = "AllowAPIGatewayInvokeCustomerLogin"
  action        = "lambda:InvokeFunction"
  function_name = data.terraform_remote_state.lambda.outputs.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_apigatewayv2_api.main.execution_arn}/*/${local.auth_route_key}"
}

# --- Route 2: everything else -> the app's public LoadBalancer ---
#
# Public HTTP proxy, not a private VPC Link: the app is already reachable on
# a public ELB (see auto-repair-shop's k8s/manifests/overlays/lab, used
# because Learner Lab has no ALB Controller/IRSA for a private path), and a
# VPC Link needs an IAM role we can't create there either. Recorded as a
# deliberate Lab-mode tradeoff, not an oversight — see infra-k8s issue #5.
#
# JWT validation is NOT duplicated here: this is a plain proxy for every
# route (public and protected alike). The app's own auth middleware — already
# correct, zero extra DB calls — is what actually enforces auth, exactly as
# it does today without the gateway in front of it.
#
# The ELB's hostname isn't a Terraform-managed resource (it's created by
# Kubernetes' in-tree AWS provider from the app's LoadBalancer Service, not
# by any `apply` here), so there's no output to read via terraform_remote_state.
# The app's own deploy workflow publishes it to this SSM parameter as the
# last step of every deploy — see auto-repair-shop's docker.yml.
data "aws_ssm_parameter" "app_backend_host" {
  name = "/${var.project}/${local.environment}/app-backend-host"
}

resource "aws_apigatewayv2_integration" "app" {
  api_id                 = aws_apigatewayv2_api.main.id
  integration_type       = "HTTP_PROXY"
  integration_method     = "ANY"
  integration_uri        = "http://${data.aws_ssm_parameter.app_backend_host.value}/{proxy}"
  payload_format_version = "1.0"
}

resource "aws_apigatewayv2_route" "app_proxy" {
  api_id    = aws_apigatewayv2_api.main.id
  route_key = "ANY /{proxy+}"
  target    = "integrations/${aws_apigatewayv2_integration.app.id}"
}

# --- Stage ---

resource "aws_apigatewayv2_stage" "main" {
  api_id      = aws_apigatewayv2_api.main.id
  name        = local.environment
  auto_deploy = true

  default_route_settings {
    throttling_rate_limit  = var.default_rate_limit
    throttling_burst_limit = var.default_burst_limit
  }

  # Tighter throttle on the auth route specifically, per issue #5's
  # "rate limit nas rotas de autenticação" requirement.
  route_settings {
    route_key              = local.auth_route_key
    throttling_rate_limit  = var.auth_route_rate_limit
    throttling_burst_limit = var.auth_route_burst_limit
  }

  tags = local.tags
}
