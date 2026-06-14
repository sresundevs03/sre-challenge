# SRE Technical Challenge
# AWS Serverless Architecture
# Owner: sresundevs03@gmail.com
#
# Resources: VPC · API Gateway · Lambda · ElastiCache Redis · S3
# Managed by: Terraform
#
# DESTROY COMMAND:
#   aws s3 rm s3://BUCKET_NAME --recursive
#   terraform destroy --auto-approve

locals {
  prefix = "${var.project_name}-${var.environment}"
}

# ── VPC ───────────────────────────────────────────────────────────────────────
module "vpc" {
  source = "./modules/vpc"

  prefix               = local.prefix
  vpc_cidr             = var.vpc_cidr
  public_subnet_cidrs  = var.public_subnet_cidrs
  private_subnet_cidrs = var.private_subnet_cidrs
  availability_zones   = var.availability_zones
}

# ── Security Groups ───────────────────────────────────────────────────────────
module "security_groups" {
  source = "./modules/security_groups"

  prefix = local.prefix
  vpc_id = module.vpc.vpc_id
}

# ── S3 ────────────────────────────────────────────────────────────────────────
module "s3" {
  source = "./modules/s3"

  prefix = local.prefix
}

# ── S3 Bucket Policy ─────────────────────────────────────────────────────────
# Defined here (not in the S3 module) to avoid a circular dependency:
# module.iam needs module.s3.bucket_arn; module.s3 would need module.iam.processor_role_arn.
resource "aws_s3_bucket_policy" "results" {
  bucket = module.s3.bucket_id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "AllowLambdaProcessorOnly"
        Effect = "Allow"
        Principal = {
          AWS = module.iam.processor_role_arn
        }
        Action = [
          "s3:PutObject",
          "s3:GetObject"
        ]
        Resource = "${module.s3.bucket_arn}/results/*"
      },
      {
        Sid       = "DenyAllOthers"
        Effect    = "Deny"
        Principal = "*"
        Action    = "s3:*"
        Resource = [
          module.s3.bucket_arn,
          "${module.s3.bucket_arn}/*"
        ]
        Condition = {
          StringNotEquals = {
            "aws:PrincipalArn" = module.iam.processor_role_arn
          }
        }
      },
      {
        Sid       = "DenyNonSSL"
        Effect    = "Deny"
        Principal = "*"
        Action    = "s3:*"
        Resource = [
          module.s3.bucket_arn,
          "${module.s3.bucket_arn}/*"
        ]
        Condition = {
          Bool = { "aws:SecureTransport" = "false" }
        }
      }
    ]
  })
}

# ── IAM ───────────────────────────────────────────────────────────────────────
module "iam" {
  source = "./modules/iam"

  prefix        = local.prefix
  s3_bucket_arn = module.s3.bucket_arn
}

# ── ElastiCache Redis ─────────────────────────────────────────────────────────
module "elasticache" {
  source = "./modules/elasticache"

  prefix            = local.prefix
  subnet_ids        = module.vpc.private_subnet_ids
  security_group_id = module.security_groups.redis_sg_id
  cluster_name      = "sre-qa-redis"
}

# ── SNS — alertas de expiración ───────────────────────────────────────────────
resource "aws_sns_topic" "expiry_alerts" {
  name = "${local.prefix}-expiry-alerts"

  tags = { Name = "${local.prefix}-expiry-alerts" }
}

resource "aws_sns_topic_subscription" "email" {
  topic_arn = aws_sns_topic.expiry_alerts.arn
  protocol  = "email"
  endpoint  = var.owner_email
}

# ── Lambda ────────────────────────────────────────────────────────────────────
module "lambda" {
  source = "./modules/lambda"

  prefix                  = local.prefix
  subnet_ids              = module.vpc.private_subnet_ids
  security_group_id       = module.security_groups.lambda_sg_id
  s3_bucket_name          = module.s3.bucket_name
  s3_bucket_arn           = module.s3.bucket_arn
  redis_host              = module.elasticache.redis_endpoint
  redis_port              = module.elasticache.redis_port
  processor_role_arn      = module.iam.processor_role_arn
  expiry_checker_role_arn = module.iam.expiry_checker_role_arn
  expiry_date             = var.expiry_date
  owner_email             = var.owner_email
  project_name            = var.project_name
  sns_topic_arn           = aws_sns_topic.expiry_alerts.arn
}

# ── API Gateway ───────────────────────────────────────────────────────────────
module "api_gateway" {
  source = "./modules/api_gateway"

  prefix               = local.prefix
  lambda_function_arn  = module.lambda.processor_function_arn
  lambda_function_name = module.lambda.processor_function_name
  aws_region           = var.aws_region
}

# ── EventBridge — revisión diaria de expiración ───────────────────────────────
resource "aws_cloudwatch_event_rule" "daily_expiry_check" {
  name                = "${local.prefix}-daily-expiry-check"
  description         = "Trigger expiry checker Lambda daily"
  schedule_expression = "rate(1 day)"
}

resource "aws_cloudwatch_event_target" "expiry_checker" {
  rule      = aws_cloudwatch_event_rule.daily_expiry_check.name
  target_id = "ExpiryCheckerLambda"
  arn       = module.lambda.expiry_checker_function_arn
}

resource "aws_lambda_permission" "allow_eventbridge" {
  statement_id  = "AllowEventBridgeInvoke"
  action        = "lambda:InvokeFunction"
  function_name = module.lambda.expiry_checker_function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.daily_expiry_check.arn
}
