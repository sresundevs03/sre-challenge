variable "prefix" {
  description = "Resource name prefix (project-environment)"
  type        = string
}

variable "lambda_function_arn" {
  description = "ARN of the processor Lambda function"
  type        = string
}

variable "lambda_function_name" {
  description = "Name of the processor Lambda function"
  type        = string
}

variable "aws_region" {
  description = "AWS region"
  type        = string
}
