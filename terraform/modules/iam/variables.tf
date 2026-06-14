variable "prefix" {
  description = "Resource name prefix (project-environment)"
  type        = string
}

variable "s3_bucket_arn" {
  description = "ARN of the S3 results bucket"
  type        = string
}
