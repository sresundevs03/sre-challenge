output "bucket_name" {
  description = "S3 bucket name"
  value       = aws_s3_bucket.results.bucket
}

output "bucket_arn" {
  description = "S3 bucket ARN"
  value       = aws_s3_bucket.results.arn
}

output "bucket_id" {
  description = "S3 bucket ID (same as bucket name, used for aws_s3_bucket_policy)"
  value       = aws_s3_bucket.results.id
}
