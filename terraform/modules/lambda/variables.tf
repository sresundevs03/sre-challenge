variable "prefix" {
  description = "Resource name prefix (project-environment)"
  type        = string
}

variable "subnet_ids" {
  description = "Private subnet IDs where Lambda runs"
  type        = list(string)
}

variable "security_group_id" {
  description = "Security group ID for Lambda"
  type        = string
}

variable "s3_bucket_name" {
  description = "S3 bucket name for storing results"
  type        = string
}

variable "s3_bucket_arn" {
  description = "S3 bucket ARN"
  type        = string
}

variable "redis_host" {
  description = "ElastiCache Redis endpoint hostname"
  type        = string
}

variable "redis_port" {
  description = "ElastiCache Redis port"
  type        = number
  default     = 6379
}

variable "processor_role_arn" {
  description = "IAM role ARN for the processor Lambda"
  type        = string
}

variable "expiry_checker_role_arn" {
  description = "IAM role ARN for the expiry checker Lambda"
  type        = string
}

variable "expiry_date" {
  description = "Infrastructure expiry date (YYYY-MM-DD)"
  type        = string
}

variable "owner_email" {
  description = "Owner email address"
  type        = string
}

variable "project_name" {
  description = "Project name"
  type        = string
}

variable "sns_topic_arn" {
  description = "SNS topic ARN for expiry alerts"
  type        = string
}
