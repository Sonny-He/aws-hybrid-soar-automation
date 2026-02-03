# ============================================================================
# SOAR System Outputs - Add to your existing output.tf
# ============================================================================

# ECS Cluster Information
output "soar_ecs_cluster_name" {
  description = "Name of the SOAR ECS cluster"
  value       = aws_ecs_cluster.soar.name
}

output "soar_ecs_cluster_arn" {
  description = "ARN of the SOAR ECS cluster"
  value       = aws_ecs_cluster.soar.arn
}

output "soar_ecs_service_name" {
  description = "Name of the SOAR ECS service"
  value       = aws_ecs_service.soar.name
}

# ECR Repository
output "soar_ecr_repository_url" {
  description = "URL of the SOAR ECR repository (push Docker images here)"
  value       = aws_ecr_repository.soar.repository_url
}

output "soar_ecr_repository_name" {
  description = "Name of the SOAR ECR repository"
  value       = aws_ecr_repository.soar.name
}

# EventBridge
output "soar_eventbridge_bus_name" {
  description = "Name of the SOAR EventBridge event bus"
  value       = aws_cloudwatch_event_bus.soar.name
}

output "soar_eventbridge_bus_arn" {
  description = "ARN of the SOAR EventBridge event bus"
  value       = aws_cloudwatch_event_bus.soar.arn
}

# SQS Queues
output "soar_sqs_high_priority_url" {
  description = "URL of the high-priority SQS queue"
  value       = aws_sqs_queue.soar_high_priority.url
}

output "soar_sqs_medium_priority_url" {
  description = "URL of the medium-priority SQS queue"
  value       = aws_sqs_queue.soar_medium_priority.url
}

output "soar_sqs_low_priority_url" {
  description = "URL of the low-priority SQS queue"
  value       = aws_sqs_queue.soar_low_priority.url
}

output "soar_sqs_dlq_url" {
  description = "URL of the Dead Letter Queue (failed messages)"
  value       = aws_sqs_queue.soar_dlq.url
}

# Lambda Functions
output "soar_lambda_email_notifier_arn" {
  description = "ARN of the email notifier Lambda function"
  value       = aws_lambda_function.email_notifier.arn
}

output "soar_lambda_s3_logger_arn" {
  description = "ARN of the S3 logger Lambda function"
  value       = aws_lambda_function.s3_logger.arn
}

output "soar_lambda_ip_blocker_arn" {
  description = "ARN of the IP blocker Lambda function"
  value       = aws_lambda_function.ip_blocker.arn
}

# S3 Bucket
output "soar_logs_bucket_name" {
  description = "Name of the S3 bucket for SOAR logs"
  value       = aws_s3_bucket.soar_logs.id
}

output "soar_logs_bucket_arn" {
  description = "ARN of the S3 bucket for SOAR logs"
  value       = aws_s3_bucket.soar_logs.arn
}

# SNS Topic
output "soar_sns_topic_arn" {
  description = "ARN of the SNS topic for SOAR alerts"
  value       = aws_sns_topic.soar_alerts.arn
}

# Security Group
output "soar_security_group_id" {
  description = "ID of the SOAR ECS security group"
  value       = aws_security_group.soar.id
}

output "soar_docker_commands" {
  description = "Commands to build and push SOAR Docker image"
  value = {
    login = "aws ecr get-login-password --region ${var.aws_region} --profile student | docker login --username AWS --password-stdin ${split("/", aws_ecr_repository.soar.repository_url)[0]}"
    build = "docker build -t ${var.project_name}-soar ./soar-app"
    tag   = "docker tag ${var.project_name}-soar:latest ${aws_ecr_repository.soar.repository_url}:latest"
    push  = "docker push ${aws_ecr_repository.soar.repository_url}:latest"
  }
}

output "soar_deployment_instructions" {
  description = "Quick guide to deploy the SOAR system"
  value = {
    step_1 = "Build Docker image: cd soar-app && docker build -t ${var.project_name}-soar ."
    step_2 = "Login to ECR: aws ecr get-login-password --region ${var.aws_region} --profile student | docker login --username AWS --password-stdin ${split("/", aws_ecr_repository.soar.repository_url)[0]}"
    step_3 = "Tag image: docker tag ${var.project_name}-soar:latest ${aws_ecr_repository.soar.repository_url}:latest"
    step_4 = "Push to ECR: docker push ${aws_ecr_repository.soar.repository_url}:latest"
    step_5 = "ECS will automatically pull and deploy the new image"
  }
}

# Testing Information
output "soar_testing_info" {
  description = "Information for testing the SOAR system"
  value = {
    eventbridge_test_command = "aws events put-events --entries '[{\"Source\":\"soar.test\",\"DetailType\":\"SecurityEvent\",\"Detail\":\"{\\\"severity\\\":\\\"high\\\",\\\"message\\\":\\\"Test event\\\"}\",\"EventBusName\":\"${aws_cloudwatch_event_bus.soar.name}\"}]'"
    sqs_check_command        = "aws sqs get-queue-attributes --queue-url ${aws_sqs_queue.soar_high_priority.url} --attribute-names ApproximateNumberOfMessages"
    ecs_logs_command         = "aws logs tail /ecs/${var.project_name}-soar --follow"
    lambda_logs_command      = "aws logs tail /aws/lambda/${aws_lambda_function.email_notifier.function_name} --follow"
  }
}

# Monitoring Links
output "soar_monitoring_links" {
  description = "Links to AWS Console for monitoring"
  value = {
    ecs_service      = "https://${var.aws_region}.console.aws.amazon.com/ecs/v2/clusters/${aws_ecs_cluster.soar.name}/services/${aws_ecs_service.soar.name}"
    eventbridge_bus  = "https://${var.aws_region}.console.aws.amazon.com/events/home?region=${var.aws_region}#/eventbus/${aws_cloudwatch_event_bus.soar.name}"
    sqs_queues       = "https://${var.aws_region}.console.aws.amazon.com/sqs/v2/home?region=${var.aws_region}"
    lambda_functions = "https://${var.aws_region}.console.aws.amazon.com/lambda/home?region=${var.aws_region}#/functions"
    cloudwatch_logs  = "https://${var.aws_region}.console.aws.amazon.com/cloudwatch/home?region=${var.aws_region}#logsV2:log-groups"
    s3_logs_bucket   = "https://s3.console.aws.amazon.com/s3/buckets/${aws_s3_bucket.soar_logs.id}"
  }
}

# Integration Information
output "soar_integration_info" {
  description = "Information for integrating with existing monitoring"
  value = {
    prometheus_metrics_endpoint = "Service discovery will automatically find ECS tasks"
    grafana_dashboard_note      = "Import SOAR dashboard from /monitoring/dashboards/soar.json"
    loki_log_collection         = "Configure Promtail to scrape ECS logs from CloudWatch"
  }
}
