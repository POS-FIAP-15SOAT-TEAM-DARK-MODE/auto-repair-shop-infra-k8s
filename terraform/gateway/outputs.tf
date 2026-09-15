output "environment" {
  value = local.environment
}

output "api_endpoint" {
  description = "Public base URL. POST {this}/auth/customer-login for a token; everything else proxies through to the app."
  value       = aws_apigatewayv2_stage.main.invoke_url
}

output "customer_login_url" {
  value = "${aws_apigatewayv2_stage.main.invoke_url}/auth/customer-login"
}
