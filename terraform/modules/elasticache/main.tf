resource "aws_elasticache_subnet_group" "main" {
  name       = "${var.prefix}-redis-subnet-group"
  subnet_ids = var.subnet_ids

  tags = { Name = "${var.prefix}-redis-subnet-group" }
}

resource "aws_elasticache_cluster" "redis" {
  cluster_id           = var.cluster_name
  engine               = "redis"
  node_type            = "cache.t3.micro"
  num_cache_nodes      = 1
  engine_version       = "7.1"
  parameter_group_name = "default.redis7"
  port                 = 6379

  subnet_group_name  = aws_elasticache_subnet_group.main.name
  security_group_ids = [var.security_group_id]

  apply_immediately          = true
  snapshot_retention_limit   = 0

  tags = { Name = "${var.prefix}-redis" }
}
