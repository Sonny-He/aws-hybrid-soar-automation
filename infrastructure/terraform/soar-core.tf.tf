# ============================================================================
# SOAR Infrastructure Fix - Add Lambda Direct Targets
# ============================================================================
# This adds Lambda functions as direct EventBridge targets alongside SQS
# so that high-priority events trigger ALL response actions
# ============================================================================

# ----------------------------------------------------------------------------
# High Priority - Additional Lambda Targets
# ----------------------------------------------------------------------------

# Direct trigger for Email Notifier (in addition to SQS)
resource "aws_cloudwatch_event_target" "soar_high_priority_email" {
  rule           = aws_cloudwatch_event_rule.soar_high_priority.name
  event_bus_name = aws_cloudwatch_event_bus.soar.name
  target_id      = "HighPriorityEmailLambda"
  arn            = aws_lambda_function.email_notifier.arn
}

# Direct trigger for S3 Logger (in addition to SQS)
resource "aws_cloudwatch_event_target" "soar_high_priority_s3" {
  rule           = aws_cloudwatch_event_rule.soar_high_priority.name
  event_bus_name = aws_cloudwatch_event_bus.soar.name
  target_id      = "HighPriorityS3Lambda"
  arn            = aws_lambda_function.s3_logger.arn
}

# Direct trigger for IP Blocker (in addition to SQS)
resource "aws_cloudwatch_event_target" "soar_high_priority_ip_blocker" {
  rule           = aws_cloudwatch_event_rule.soar_high_priority.name
  event_bus_name = aws_cloudwatch_event_bus.soar.name
  target_id      = "HighPriorityIPBlocker"
  arn            = aws_lambda_function.ip_blocker.arn
}

# ----------------------------------------------------------------------------
# Lambda Permissions - Allow EventBridge to Invoke
# ----------------------------------------------------------------------------

# Email Notifier - EventBridge permission
resource "aws_lambda_permission" "email_notifier_eventbridge" {
  statement_id  = "AllowExecutionFromEventBridge"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.email_notifier.function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.soar_high_priority.arn
}

# S3 Logger - EventBridge permission
resource "aws_lambda_permission" "s3_logger_eventbridge" {
  statement_id  = "AllowExecutionFromEventBridge"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.s3_logger.function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.soar_high_priority.arn
}

# IP Blocker - EventBridge permission
resource "aws_lambda_permission" "ip_blocker_eventbridge" {
  statement_id  = "AllowExecutionFromEventBridge"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.ip_blocker.function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.soar_high_priority.arn
}

# ----------------------------------------------------------------------------
# Medium Priority - Add S3 Logger Direct Target
# ----------------------------------------------------------------------------

# Direct trigger for S3 Logger (in addition to SQS)
resource "aws_cloudwatch_event_target" "soar_medium_priority_s3" {
  rule           = aws_cloudwatch_event_rule.soar_medium_priority.name
  event_bus_name = aws_cloudwatch_event_bus.soar.name
  target_id      = "MediumPriorityS3Lambda"
  arn            = aws_lambda_function.s3_logger.arn
}

# S3 Logger - EventBridge permission for medium priority
resource "aws_lambda_permission" "s3_logger_eventbridge_medium" {
  statement_id  = "AllowExecutionFromEventBridgeMedium"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.s3_logger.function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.soar_medium_priority.arn
}

# ----------------------------------------------------------------------------
# Low Priority - Add S3 Logger Direct Target
# ----------------------------------------------------------------------------

# Direct trigger for S3 Logger (in addition to SQS)
resource "aws_cloudwatch_event_target" "soar_low_priority_s3" {
  rule           = aws_cloudwatch_event_rule.soar_low_priority.name
  event_bus_name = aws_cloudwatch_event_bus.soar.name
  target_id      = "LowPriorityS3Lambda"
  arn            = aws_lambda_function.s3_logger.arn
}

# S3 Logger - EventBridge permission for low priority
resource "aws_lambda_permission" "s3_logger_eventbridge_low" {
  statement_id  = "AllowExecutionFromEventBridgeLow"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.s3_logger.function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.soar_low_priority.arn
}
