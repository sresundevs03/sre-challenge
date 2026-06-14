output "processor_role_arn" {
  description = "IAM role ARN for the processor Lambda"
  value       = aws_iam_role.processor.arn
}

output "expiry_checker_role_arn" {
  description = "IAM role ARN for the expiry checker Lambda"
  value       = aws_iam_role.expiry_checker.arn
}
