variable "prefix" {
  description = "Resource name prefix (project-environment)"
  type        = string
}

variable "lambda_role_arn" {
  description = "ARN of the Lambda processor IAM role allowed to access the bucket"
  type        = string
  default     = ""
}
