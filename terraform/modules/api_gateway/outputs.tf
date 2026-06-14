output "api_endpoint" {
  description = "HTTP API invoke URL"
  value       = aws_apigatewayv2_stage.default.invoke_url
}

output "api_id" {
  description = "HTTP API ID"
  value       = aws_apigatewayv2_api.main.id
}
