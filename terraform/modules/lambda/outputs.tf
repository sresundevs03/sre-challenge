output "processor_function_arn" {
  description = "ARN of the processor Lambda function"
  value       = aws_lambda_function.processor.arn
}

output "processor_function_name" {
  description = "Name of the processor Lambda function"
  value       = aws_lambda_function.processor.function_name
}

output "expiry_checker_function_arn" {
  description = "ARN of the expiry checker Lambda function"
  value       = aws_lambda_function.expiry_checker.arn
}

output "expiry_checker_function_name" {
  description = "Name of the expiry checker Lambda function"
  value       = aws_lambda_function.expiry_checker.function_name
}
