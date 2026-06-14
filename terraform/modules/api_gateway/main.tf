resource "aws_cloudwatch_log_group" "api_access" {
  name              = "/aws/apigateway/${var.prefix}-api"
  retention_in_days = 7
}

resource "aws_apigatewayv2_api" "main" {
  name          = "${var.prefix}-api"
  protocol_type = "HTTP"
  description   = "SRE Challenge HTTP API"

  cors_configuration {
    allow_headers = ["Content-Type", "X-Request-Id"]
    allow_methods = ["POST", "OPTIONS"]
    allow_origins = ["*"]
    max_age       = 300
  }

  tags = { Name = "${var.prefix}-api" }
}

resource "aws_apigatewayv2_integration" "lambda" {
  api_id                 = aws_apigatewayv2_api.main.id
  integration_type       = "AWS_PROXY"
  integration_uri        = var.lambda_function_arn
  payload_format_version = "2.0"
}

resource "aws_apigatewayv2_route" "process" {
  api_id    = aws_apigatewayv2_api.main.id
  route_key = "POST /process"
  target    = "integrations/${aws_apigatewayv2_integration.lambda.id}"
}

resource "aws_apigatewayv2_stage" "default" {
  api_id      = aws_apigatewayv2_api.main.id
  name        = "$default"
  auto_deploy = true

  access_log_settings {
    destination_arn = aws_cloudwatch_log_group.api_access.arn
    format = jsonencode({
      requestId      = "$context.requestId"
      ip             = "$context.identity.sourceIp"
      httpMethod     = "$context.httpMethod"
      routeKey       = "$context.routeKey"
      status         = "$context.status"
      responseLength = "$context.responseLength"
      latency        = "$context.integrationLatency"
      errorMessage   = "$context.integrationErrorMessage"
    })
  }

  default_route_settings {
    throttling_burst_limit = 10
    throttling_rate_limit  = 5
  }

  tags = { Name = "${var.prefix}-api-stage" }
}

resource "aws_lambda_permission" "api_gateway" {
  statement_id  = "AllowAPIGatewayInvoke"
  action        = "lambda:InvokeFunction"
  function_name = var.lambda_function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_apigatewayv2_api.main.execution_arn}/*/*/process"
}
