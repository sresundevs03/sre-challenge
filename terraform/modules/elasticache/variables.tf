variable "prefix" {
  description = "Resource name prefix (project-environment)"
  type        = string
}

variable "subnet_ids" {
  description = "List of private subnet IDs for the ElastiCache subnet group"
  type        = list(string)
}

variable "security_group_id" {
  description = "Security group ID to attach to the Redis cluster"
  type        = string
}

variable "cluster_name" {
  description = "ElastiCache cluster ID (max 20 characters)"
  type        = string
  default     = "sre-qa-redis"
}
