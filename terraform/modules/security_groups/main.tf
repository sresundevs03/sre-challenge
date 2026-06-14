# Separate SG resources from rules to avoid circular dependency
resource "aws_security_group" "lambda" {
  name        = "${var.prefix}-sg-lambda"
  description = "Security group for Lambda functions"
  vpc_id      = var.vpc_id

  tags = { Name = "${var.prefix}-sg-lambda" }
}

resource "aws_security_group" "redis" {
  name        = "${var.prefix}-sg-redis"
  description = "Security group for ElastiCache Redis"
  vpc_id      = var.vpc_id

  tags = { Name = "${var.prefix}-sg-redis" }
}

# ── Lambda egress rules ───────────────────────────────────────────────────────
resource "aws_security_group_rule" "lambda_egress_redis" {
  type                     = "egress"
  description              = "Lambda to Redis"
  from_port                = 6379
  to_port                  = 6379
  protocol                 = "tcp"
  security_group_id        = aws_security_group.lambda.id
  source_security_group_id = aws_security_group.redis.id
}

resource "aws_security_group_rule" "lambda_egress_https" {
  type              = "egress"
  description       = "HTTPS for S3 VPC endpoint and AWS APIs"
  from_port         = 443
  to_port           = 443
  protocol          = "tcp"
  security_group_id = aws_security_group.lambda.id
  cidr_blocks       = ["0.0.0.0/0"]
}

resource "aws_security_group_rule" "lambda_egress_dns_udp" {
  type              = "egress"
  description       = "DNS UDP"
  from_port         = 53
  to_port           = 53
  protocol          = "udp"
  security_group_id = aws_security_group.lambda.id
  cidr_blocks       = ["0.0.0.0/0"]
}

resource "aws_security_group_rule" "lambda_egress_dns_tcp" {
  type              = "egress"
  description       = "DNS TCP"
  from_port         = 53
  to_port           = 53
  protocol          = "tcp"
  security_group_id = aws_security_group.lambda.id
  cidr_blocks       = ["0.0.0.0/0"]
}

# ── Redis ingress — Lambda only ───────────────────────────────────────────────
resource "aws_security_group_rule" "redis_ingress_lambda" {
  type                     = "ingress"
  description              = "Redis from Lambda only"
  from_port                = 6379
  to_port                  = 6379
  protocol                 = "tcp"
  security_group_id        = aws_security_group.redis.id
  source_security_group_id = aws_security_group.lambda.id
}
