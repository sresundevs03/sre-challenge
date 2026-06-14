data "aws_iam_policy_document" "lambda_assume_role" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["lambda.amazonaws.com"]
    }
  }
}

# ── Processor Lambda ──────────────────────────────────────────────────────────
resource "aws_iam_role" "processor" {
  name               = "${var.prefix}-role-processor"
  assume_role_policy = data.aws_iam_policy_document.lambda_assume_role.json
}

resource "aws_iam_role_policy_attachment" "processor_vpc" {
  role       = aws_iam_role.processor.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaVPCAccessExecutionRole"
}

resource "aws_iam_role_policy" "processor_s3" {
  name = "${var.prefix}-policy-processor-s3"
  role = aws_iam_role.processor.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "s3:PutObject",
          "s3:GetObject"
        ]
        Resource = "${var.s3_bucket_arn}/results/*"
      }
    ]
  })
}

# ── Expiry Checker Lambda ─────────────────────────────────────────────────────
resource "aws_iam_role" "expiry_checker" {
  name               = "${var.prefix}-role-expiry-checker"
  assume_role_policy = data.aws_iam_policy_document.lambda_assume_role.json
}

resource "aws_iam_role_policy_attachment" "expiry_checker_basic" {
  role       = aws_iam_role.expiry_checker.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

resource "aws_iam_role_policy" "expiry_checker_sns" {
  name = "${var.prefix}-policy-expiry-checker-sns"
  role = aws_iam_role.expiry_checker.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = ["sns:Publish"]
        Resource = "*"
      }
    ]
  })
}
