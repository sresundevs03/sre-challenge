output "api_endpoint" {
  description = "HTTP API endpoint URL — POST /process"
  value       = "${module.api_gateway.api_endpoint}process"
}

output "s3_bucket_name" {
  description = "S3 bucket name for results"
  value       = module.s3.bucket_name
}

output "redis_endpoint" {
  description = "ElastiCache Redis endpoint"
  value       = module.elasticache.redis_endpoint
}

output "vpc_id" {
  description = "VPC ID"
  value       = module.vpc.vpc_id
}

output "lambda_processor_name" {
  description = "Processor Lambda function name"
  value       = module.lambda.processor_function_name
}

output "sns_topic_arn" {
  description = "SNS topic ARN for expiry alerts"
  value       = aws_sns_topic.expiry_alerts.arn
}
