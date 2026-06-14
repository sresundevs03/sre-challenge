output "lambda_sg_id" {
  description = "Security group ID for Lambda functions"
  value       = aws_security_group.lambda.id
}

output "redis_sg_id" {
  description = "Security group ID for ElastiCache Redis"
  value       = aws_security_group.redis.id
}
