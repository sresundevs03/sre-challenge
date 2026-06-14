variable "prefix" {
  description = "Resource name prefix (project-environment)"
  type        = string
}

variable "vpc_id" {
  description = "VPC ID where security groups will be created"
  type        = string
}
