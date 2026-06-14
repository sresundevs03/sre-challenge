# ── Build Lambda package (pip install + zip) ──────────────────────────────────
resource "null_resource" "build_package" {
  triggers = {
    handler_hash      = filemd5("${path.root}/../lambda/handler.py")
    expiry_hash       = filemd5("${path.root}/../lambda/expiry_checker.py")
    requirements_hash = filemd5("${path.root}/../lambda/requirements.txt")
  }

  provisioner "local-exec" {
    working_dir = "${path.root}/.."
    interpreter = ["PowerShell", "-Command"]
    command     = <<-EOT
      if (Test-Path lambda/package) { Remove-Item lambda/package -Recurse -Force }
      New-Item lambda/package -ItemType Directory | Out-Null
      python -m pip install -r lambda/requirements.txt -t lambda/package --quiet
      Copy-Item lambda/handler.py lambda/package/
      Copy-Item lambda/expiry_checker.py lambda/package/
      Write-Host "Lambda package built successfully."
    EOT
  }
}

data "archive_file" "lambda_zip" {
  type        = "zip"
  source_dir  = "${path.root}/../lambda/package"
  output_path = "${path.root}/../lambda/function.zip"

  depends_on = [null_resource.build_package]
}

# ── CloudWatch Log Groups ─────────────────────────────────────────────────────
resource "aws_cloudwatch_log_group" "processor" {
  name              = "/aws/lambda/${var.prefix}-processor"
  retention_in_days = 7
}

resource "aws_cloudwatch_log_group" "expiry_checker" {
  name              = "/aws/lambda/${var.prefix}-expiry-checker"
  retention_in_days = 7
}

# ── Processor Lambda ──────────────────────────────────────────────────────────
resource "aws_lambda_function" "processor" {
  function_name = "${var.prefix}-processor"
  role          = var.processor_role_arn
  runtime       = "python3.11"
  handler       = "handler.handler"
  timeout       = 30
  memory_size   = 256

  filename         = data.archive_file.lambda_zip.output_path
  source_code_hash = data.archive_file.lambda_zip.output_base64sha256

  vpc_config {
    subnet_ids         = var.subnet_ids
    security_group_ids = [var.security_group_id]
  }

  environment {
    variables = {
      REDIS_HOST = var.redis_host
      REDIS_PORT = tostring(var.redis_port)
      S3_BUCKET  = var.s3_bucket_name
    }
  }

  depends_on = [aws_cloudwatch_log_group.processor]

  tags = { Name = "${var.prefix}-processor" }
}

# ── Expiry Checker Lambda (no VPC — calls SNS public endpoint) ────────────────
resource "aws_lambda_function" "expiry_checker" {
  function_name = "${var.prefix}-expiry-checker"
  role          = var.expiry_checker_role_arn
  runtime       = "python3.11"
  handler       = "expiry_checker.handler"
  timeout       = 60
  memory_size   = 128

  filename         = data.archive_file.lambda_zip.output_path
  source_code_hash = data.archive_file.lambda_zip.output_base64sha256

  environment {
    variables = {
      EXPIRY_DATE   = var.expiry_date
      OWNER_EMAIL   = var.owner_email
      PROJECT_NAME  = var.project_name
      SNS_TOPIC_ARN = var.sns_topic_arn
    }
  }

  depends_on = [aws_cloudwatch_log_group.expiry_checker]

  tags = { Name = "${var.prefix}-expiry-checker" }
}
