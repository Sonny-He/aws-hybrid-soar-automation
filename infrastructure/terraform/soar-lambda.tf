# ============================================================================
# SOAR Lambda Functions - Automated Response Actions
# ============================================================================
# This file defines Lambda functions that execute automated responses
# triggered by security events from the SOAR system
# ============================================================================

# ----------------------------------------------------------------------------
# IAM Role for Lambda Functions
# ----------------------------------------------------------------------------
resource "aws_iam_role" "soar_lambda" {
  name = "${var.project_name}-soar-lambda"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action = "sts:AssumeRole"
      Effect = "Allow"
      Principal = {
        Service = "lambda.amazonaws.com"
      }
    }]
  })

  tags = {
    Name        = "${var.project_name}-soar-lambda-role"
    Environment = var.environment
    Purpose     = "SOAR"
  }
}

# Attach basic Lambda execution policy
resource "aws_iam_role_policy_attachment" "soar_lambda_basic" {
  role       = aws_iam_role.soar_lambda.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

# VPC execution policy (for accessing VPC resources)
resource "aws_iam_role_policy_attachment" "soar_lambda_vpc" {
  role       = aws_iam_role.soar_lambda.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaVPCAccessExecutionRole"
}

# Custom policy for Lambda functions
resource "aws_iam_role_policy" "soar_lambda_custom" {
  name = "${var.project_name}-soar-lambda-policy"
  role = aws_iam_role.soar_lambda.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "sqs:ReceiveMessage",
          "sqs:DeleteMessage",
          "sqs:GetQueueAttributes"
        ]
        Resource = [
          aws_sqs_queue.soar_high_priority.arn,
          aws_sqs_queue.soar_medium_priority.arn,
          aws_sqs_queue.soar_low_priority.arn
        ]
      },
      {
        Effect = "Allow"
        Action = [
          "s3:PutObject",
          "s3:PutObjectAcl"
        ]
        Resource = "${aws_s3_bucket.soar_logs.arn}/*"
      },
      {
        Effect = "Allow"
        Action = [
          "sns:Publish"
        ]
        Resource = aws_sns_topic.soar_alerts.arn
      },
      {
        Effect = "Allow"
        Action = [
          "ses:SendEmail",
          "ses:SendRawEmail"
        ]
        Resource = "*"
      },
      {
        Effect = "Allow"
        Action = [
          "ec2:DescribeNetworkAcls",
          "ec2:CreateNetworkAclEntry",
          "ec2:DeleteNetworkAclEntry"
        ]
        Resource = "*"
      },
      {
        Effect = "Allow"
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ]
        Resource = "arn:aws:logs:${var.aws_region}:*:log-group:/aws/lambda/${var.project_name}-soar-*"
      }
    ]
  })
}

# ----------------------------------------------------------------------------
# S3 Bucket for SOAR Logs
# ----------------------------------------------------------------------------
resource "aws_s3_bucket" "soar_logs" {
  bucket        = "${var.project_name}-soar-logs-${data.aws_region.current.name}"
  force_destroy = true

  tags = {
    Name        = "${var.project_name}-soar-logs"
    Environment = var.environment
    Purpose     = "SOAR"
  }
}

# Enable versioning
resource "aws_s3_bucket_versioning" "soar_logs" {
  bucket = aws_s3_bucket.soar_logs.id

  versioning_configuration {
    status = "Enabled"
  }
}

# Enable encryption
resource "aws_s3_bucket_server_side_encryption_configuration" "soar_logs" {
  bucket = aws_s3_bucket.soar_logs.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

# Block public access
resource "aws_s3_bucket_public_access_block" "soar_logs" {
  bucket = aws_s3_bucket.soar_logs.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# Lifecycle policy - delete old logs after 90 days
resource "aws_s3_bucket_lifecycle_configuration" "soar_logs" {
  bucket = aws_s3_bucket.soar_logs.id

  rule {
    id     = "delete-old-logs"
    status = "Enabled"

    filter {}

    expiration {
      days = 90
    }
  }
}

# ----------------------------------------------------------------------------
# SNS Topic for Email Notifications
# ----------------------------------------------------------------------------
resource "aws_sns_topic" "soar_alerts" {
  name = "${var.project_name}-soar-alerts"

  tags = {
    Name        = "${var.project_name}-soar-alerts"
    Environment = var.environment
    Purpose     = "SOAR"
  }
}

# SNS Topic Subscription - Add your email here
resource "aws_sns_topic_subscription" "soar_alerts_email" {
  topic_arn = aws_sns_topic.soar_alerts.arn
  protocol  = "email"
  endpoint  = var.soar_alert_email # Add this variable to variables.tf
}

# ----------------------------------------------------------------------------
# Lambda Function 1: Email Notifier
# ----------------------------------------------------------------------------
resource "aws_lambda_function" "email_notifier" {
  filename         = "${path.module}/lambda/email_notifier.zip"
  function_name    = "${var.project_name}-soar-email-notifier"
  role             = aws_iam_role.soar_lambda.arn
  handler          = "index.handler"
  source_code_hash = filebase64sha256("${path.module}/lambda/email_notifier.zip")
  runtime          = "python3.11"
  timeout          = 60
  memory_size      = 256

  environment {
    variables = {
      SNS_TOPIC_ARN = aws_sns_topic.soar_alerts.arn
      SENDER_EMAIL  = var.soar_sender_email
    }
  }

  tags = {
    Name        = "${var.project_name}-email-notifier"
    Environment = var.environment
    Purpose     = "SOAR"
  }
}

# CloudWatch Log Group for Email Notifier
resource "aws_cloudwatch_log_group" "email_notifier" {
  name              = "/aws/lambda/${aws_lambda_function.email_notifier.function_name}"
  retention_in_days = var.cloudwatch_logs_retention

  tags = {
    Name        = "${var.project_name}-email-notifier-logs"
    Environment = var.environment
  }
}

# SQS Event Source Mapping - Trigger Lambda from high-priority queue
# resource "aws_lambda_event_source_mapping" "email_notifier_high" {
#   event_source_arn = aws_sqs_queue.soar_high_priority.arn
#   function_name    = aws_lambda_function.email_notifier.arn
#   batch_size       = 10
#   enabled          = true

#   scaling_config {
#     maximum_concurrency = 10
#   }
# }

# ----------------------------------------------------------------------------
# Lambda Function 2: S3 Logger
# ----------------------------------------------------------------------------
resource "aws_lambda_function" "s3_logger" {
  filename         = "${path.module}/lambda/s3_logger.zip"
  function_name    = "${var.project_name}-soar-s3-logger"
  role             = aws_iam_role.soar_lambda.arn
  handler          = "index.handler"
  source_code_hash = filebase64sha256("${path.module}/lambda/s3_logger.zip")
  runtime          = "python3.11"
  timeout          = 60
  memory_size      = 256

  environment {
    variables = {
      S3_BUCKET = aws_s3_bucket.soar_logs.id
      VPC_ID    = aws_vpc.main.id # ← ADD THIS LINE
    }
  }

  tags = {
    Name        = "${var.project_name}-s3-logger"
    Environment = var.environment
    Purpose     = "SOAR"
  }
}

# CloudWatch Log Group for S3 Logger
resource "aws_cloudwatch_log_group" "s3_logger" {
  name              = "/aws/lambda/${aws_lambda_function.s3_logger.function_name}"
  retention_in_days = var.cloudwatch_logs_retention

  tags = {
    Name        = "${var.project_name}-s3-logger-logs"
    Environment = var.environment
  }
}

# SQS Event Source Mapping - Trigger from all priority queues
# resource "aws_lambda_event_source_mapping" "s3_logger_high" {
#   event_source_arn = aws_sqs_queue.soar_high_priority.arn
#   function_name    = aws_lambda_function.s3_logger.arn
#   batch_size       = 10
#   enabled          = true

#   scaling_config {
#     maximum_concurrency = 10
#   }
# }

resource "aws_lambda_event_source_mapping" "s3_logger_medium" {
  event_source_arn = aws_sqs_queue.soar_medium_priority.arn
  function_name    = aws_lambda_function.s3_logger.arn
  batch_size       = 10
  enabled          = true

  scaling_config {
    maximum_concurrency = 10
  }
}

resource "aws_lambda_event_source_mapping" "s3_logger_low" {
  event_source_arn = aws_sqs_queue.soar_low_priority.arn
  function_name    = aws_lambda_function.s3_logger.arn
  batch_size       = 10
  enabled          = true

  scaling_config {
    maximum_concurrency = 10
  }
}

# ----------------------------------------------------------------------------
# Lambda Function 3: IP Blocker (Network ACL modifier)
# ----------------------------------------------------------------------------
resource "aws_lambda_function" "ip_blocker" {
  filename         = "${path.module}/lambda/ip_blocker.zip"
  function_name    = "${var.project_name}-soar-ip-blocker"
  role             = aws_iam_role.soar_lambda.arn
  handler          = "index.handler"
  source_code_hash = filebase64sha256("${path.module}/lambda/ip_blocker.zip")
  runtime          = "python3.11"
  timeout          = 60
  memory_size      = 256

  environment {
    variables = {
      VPC_ID = aws_vpc.main.id
    }
  }

  vpc_config {
    subnet_ids         = aws_subnet.private_web[*].id
    security_group_ids = [aws_security_group.soar.id]
  }

  tags = {
    Name        = "${var.project_name}-ip-blocker"
    Environment = var.environment
    Purpose     = "SOAR"
  }
}

# CloudWatch Log Group for IP Blocker
resource "aws_cloudwatch_log_group" "ip_blocker" {
  name              = "/aws/lambda/${aws_lambda_function.ip_blocker.function_name}"
  retention_in_days = var.cloudwatch_logs_retention

  tags = {
    Name        = "${var.project_name}-ip-blocker-logs"
    Environment = var.environment
  }
}

# # SQS Event Source Mapping - Only trigger from high-priority queue
# resource "aws_lambda_event_source_mapping" "ip_blocker_high" {
#   event_source_arn = aws_sqs_queue.soar_high_priority.arn
#   function_name    = aws_lambda_function.ip_blocker.arn
#   batch_size       = 10
#   enabled          = true

#   scaling_config {
#     maximum_concurrency = 5
#   }
# }

# ----------------------------------------------------------------------------
# CloudWatch Alarms for Lambda Functions
# ----------------------------------------------------------------------------

# Alarm for Lambda errors (Email Notifier)
resource "aws_cloudwatch_metric_alarm" "email_notifier_errors" {
  alarm_name          = "${var.project_name}-email-notifier-errors"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "1"
  metric_name         = "Errors"
  namespace           = "AWS/Lambda"
  period              = "300"
  statistic           = "Sum"
  threshold           = "5"
  alarm_description   = "Email notifier Lambda function has too many errors"

  dimensions = {
    FunctionName = aws_lambda_function.email_notifier.function_name
  }

  tags = {
    Name        = "${var.project_name}-email-notifier-alarm"
    Environment = var.environment
  }
}

# Alarm for Lambda throttling
resource "aws_cloudwatch_metric_alarm" "email_notifier_throttles" {
  alarm_name          = "${var.project_name}-email-notifier-throttles"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "1"
  metric_name         = "Throttles"
  namespace           = "AWS/Lambda"
  period              = "300"
  statistic           = "Sum"
  threshold           = "10"
  alarm_description   = "Email notifier Lambda is being throttled"

  dimensions = {
    FunctionName = aws_lambda_function.email_notifier.function_name
  }

  tags = {
    Name        = "${var.project_name}-email-notifier-throttle-alarm"
    Environment = var.environment
  }
}

# ----------------------------------------------------------------------------
# Lambda Insights - Enhanced monitoring (optional)
# ----------------------------------------------------------------------------
resource "aws_iam_role_policy_attachment" "lambda_insights" {
  role       = aws_iam_role.soar_lambda.name
  policy_arn = "arn:aws:iam::aws:policy/CloudWatchLambdaInsightsExecutionRolePolicy"
}
