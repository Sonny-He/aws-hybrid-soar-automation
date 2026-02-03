# ============================================================================
# SOAR System Infrastructure - Case Study 2
# ============================================================================
# This file defines the complete SOAR (Security Orchestration, Automation, 
# and Response) system using ECS Fargate, EventBridge, SQS, and Lambda
# ============================================================================

# ----------------------------------------------------------------------------
# ECR Repository - Store SOAR container images
# ----------------------------------------------------------------------------
resource "aws_ecr_repository" "soar" {
  name                 = "${var.project_name}-soar"
  force_delete         = true
  image_tag_mutability = "MUTABLE"

  image_scanning_configuration {
    scan_on_push = true
  }

  encryption_configuration {
    encryption_type = "AES256"
  }

  tags = {
    Name        = "${var.project_name}-soar-ecr"
    Environment = var.environment
    Purpose     = "SOAR"
  }
}

# ECR Lifecycle Policy - Keep only latest 10 images
resource "aws_ecr_lifecycle_policy" "soar" {
  repository = aws_ecr_repository.soar.name

  policy = jsonencode({
    rules = [{
      rulePriority = 1
      description  = "Keep last 10 images"
      selection = {
        tagStatus   = "any"
        countType   = "imageCountMoreThan"
        countNumber = 10
      }
      action = {
        type = "expire"
      }
    }]
  })
}

# ----------------------------------------------------------------------------
# ECS Cluster - Fargate for serverless container execution
# ----------------------------------------------------------------------------
resource "aws_ecs_cluster" "soar" {
  name = "${var.project_name}-soar-cluster"

  setting {
    name  = "containerInsights"
    value = "enabled"
  }

  tags = {
    Name        = "${var.project_name}-soar-cluster"
    Environment = var.environment
    Purpose     = "SOAR"
  }
}

# ECS Cluster Capacity Providers - Use Fargate for serverless
resource "aws_ecs_cluster_capacity_providers" "soar" {
  cluster_name = aws_ecs_cluster.soar.name

  capacity_providers = ["FARGATE", "FARGATE_SPOT"]

  default_capacity_provider_strategy {
    base              = 1
    weight            = 100
    capacity_provider = "FARGATE"
  }

  default_capacity_provider_strategy {
    weight            = 0
    capacity_provider = "FARGATE_SPOT"
  }
}

# ----------------------------------------------------------------------------
# CloudWatch Log Group - For ECS task logs
# ----------------------------------------------------------------------------
resource "aws_cloudwatch_log_group" "soar" {
  name              = "/ecs/${var.project_name}-soar"
  retention_in_days = var.cloudwatch_logs_retention

  tags = {
    Name        = "${var.project_name}-soar-logs"
    Environment = var.environment
  }
}

# ----------------------------------------------------------------------------
# IAM Role for ECS Task Execution
# ----------------------------------------------------------------------------
resource "aws_iam_role" "ecs_task_execution" {
  name = "${var.project_name}-ecs-task-execution"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action = "sts:AssumeRole"
      Effect = "Allow"
      Principal = {
        Service = "ecs-tasks.amazonaws.com"
      }
    }]
  })

  tags = {
    Name        = "${var.project_name}-ecs-task-execution-role"
    Environment = var.environment
  }
}

# Attach AWS managed policy for ECS task execution
resource "aws_iam_role_policy_attachment" "ecs_task_execution" {
  role       = aws_iam_role.ecs_task_execution.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

# Additional policy for ECR access
resource "aws_iam_role_policy" "ecs_task_execution_ecr" {
  name = "${var.project_name}-ecs-ecr-access"
  role = aws_iam_role.ecs_task_execution.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Action = [
        "ecr:GetAuthorizationToken",
        "ecr:BatchCheckLayerAvailability",
        "ecr:GetDownloadUrlForLayer",
        "ecr:BatchGetImage"
      ]
      Resource = "*"
    }]
  })
}

# ----------------------------------------------------------------------------
# IAM Role for ECS Task (application permissions)
# ----------------------------------------------------------------------------
resource "aws_iam_role" "ecs_task" {
  name = "${var.project_name}-ecs-task"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action = "sts:AssumeRole"
      Effect = "Allow"
      Principal = {
        Service = "ecs-tasks.amazonaws.com"
      }
    }]
  })

  tags = {
    Name        = "${var.project_name}-ecs-task-role"
    Environment = var.environment
  }
}

# Policy for ECS task to send events to EventBridge
resource "aws_iam_role_policy" "ecs_task_eventbridge" {
  name = "${var.project_name}-ecs-eventbridge"
  role = aws_iam_role.ecs_task.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Action = [
        "events:PutEvents"
      ]
      Resource = aws_cloudwatch_event_bus.soar.arn
    }]
  })
}

# Policy for CloudWatch Logs
resource "aws_iam_role_policy" "ecs_task_logs" {
  name = "${var.project_name}-ecs-logs"
  role = aws_iam_role.ecs_task.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Action = [
        "logs:CreateLogGroup",
        "logs:CreateLogStream",
        "logs:PutLogEvents"
      ]
      Resource = "${aws_cloudwatch_log_group.soar.arn}:*"
    }]
  })
}

# ----------------------------------------------------------------------------
# Security Group for SOAR ECS Tasks
# ----------------------------------------------------------------------------
resource "aws_security_group" "soar" {
  name_prefix = "${var.project_name}-soar-ecs-"
  vpc_id      = aws_vpc.main.id
  description = "Security group for SOAR ECS tasks"

  # Allow syslog from web servers (UDP 5140 - non-privileged port)
  ingress {
    from_port = 5140
    to_port   = 5140
    protocol  = "udp"
    cidr_blocks = [
      aws_subnet.private_web[0].cidr_block,
      aws_subnet.private_web[1].cidr_block
    ]
    description = "Syslog from web servers (non-privileged port)"
  }

  # Allow syslog from on-premises via VPN (UDP 5140 - non-privileged port)
  ingress {
    from_port   = 5140
    to_port     = 5140
    protocol    = "udp"
    cidr_blocks = ["10.8.0.0/24"]
    description = "Syslog from VPN clients (non-privileged port)"
  }

  # Allow HTTP for health checks
  ingress {
    from_port   = 8080
    to_port     = 8080
    protocol    = "tcp"
    cidr_blocks = [aws_vpc.main.cidr_block]
    description = "Health check port"
  }

  # Allow all outbound traffic
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
    description = "Allow all outbound"
  }

  tags = {
    Name        = "${var.project_name}-soar-ecs-sg"
    Environment = var.environment
    Purpose     = "SOAR"
  }
}

# ----------------------------------------------------------------------------
# ECS Task Definition - SOAR Event Collector & Rule Engine
# ----------------------------------------------------------------------------
resource "aws_ecs_task_definition" "soar" {
  family                   = "${var.project_name}-soar"
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  cpu                      = "512"  # 0.5 vCPU
  memory                   = "1024" # 1 GB RAM
  execution_role_arn       = aws_iam_role.ecs_task_execution.arn
  task_role_arn            = aws_iam_role.ecs_task.arn

  container_definitions = jsonencode([{
    name      = "soar-collector"
    image     = "${aws_ecr_repository.soar.repository_url}:latest"
    essential = true

    portMappings = [
      {
        containerPort = 5140
        protocol      = "udp"
        name          = "syslog"
      },
      {
        containerPort = 8080
        protocol      = "tcp"
        name          = "health"
      }
    ]

    environment = [
      {
        name  = "EVENTBRIDGE_BUS_NAME"
        value = aws_cloudwatch_event_bus.soar.name
      },
      {
        name  = "AWS_REGION"
        value = var.aws_region
      },
      {
        name  = "LOG_LEVEL"
        value = "INFO"
      }
    ]

    logConfiguration = {
      logDriver = "awslogs"
      options = {
        "awslogs-group"         = aws_cloudwatch_log_group.soar.name
        "awslogs-region"        = var.aws_region
        "awslogs-stream-prefix" = "soar"
      }
    }

    healthCheck = {
      command     = ["CMD-SHELL", "curl -f http://localhost:8080/health || exit 1"]
      interval    = 30
      timeout     = 5
      retries     = 3
      startPeriod = 60
    }
  }])

  tags = {
    Name        = "${var.project_name}-soar-task"
    Environment = var.environment
    Purpose     = "SOAR"
  }
}

# ----------------------------------------------------------------------------
# ECS Service - Run SOAR tasks across both AZs (Option A)
# ----------------------------------------------------------------------------
resource "aws_ecs_service" "soar" {
  name            = "${var.project_name}-soar-service"
  cluster         = aws_ecs_cluster.soar.id
  task_definition = aws_ecs_task_definition.soar.arn
  desired_count   = 2 # One task per AZ
  launch_type     = "FARGATE"

  network_configuration {
    subnets = [
      aws_subnet.private_web[0].id, # SOAR subnet A (using web subnet for now)
      aws_subnet.private_web[1].id  # SOAR subnet B
    ]
    security_groups  = [aws_security_group.soar.id]
    assign_public_ip = false
  }

  # Enable Circuit Breaker for safer deployments

  deployment_circuit_breaker {
    enable   = true
    rollback = true
  }

  # Enable ECS Exec for debugging (optional)
  enable_execute_command = true

  tags = {
    Name        = "${var.project_name}-soar-service"
    Environment = var.environment
    Purpose     = "SOAR"
  }

  depends_on = [
    aws_iam_role_policy.ecs_task_eventbridge,
    aws_iam_role_policy.ecs_task_logs
  ]
}

# Auto Scaling for ECS Service
resource "aws_appautoscaling_target" "soar" {
  max_capacity       = 10
  min_capacity       = 2
  resource_id        = "service/${aws_ecs_cluster.soar.name}/${aws_ecs_service.soar.name}"
  scalable_dimension = "ecs:service:DesiredCount"
  service_namespace  = "ecs"
}

resource "aws_appautoscaling_policy" "soar_cpu" {
  name               = "${var.project_name}-soar-cpu-scaling"
  policy_type        = "TargetTrackingScaling"
  resource_id        = aws_appautoscaling_target.soar.resource_id
  scalable_dimension = aws_appautoscaling_target.soar.scalable_dimension
  service_namespace  = aws_appautoscaling_target.soar.service_namespace

  target_tracking_scaling_policy_configuration {
    predefined_metric_specification {
      predefined_metric_type = "ECSServiceAverageCPUUtilization"
    }
    target_value = 70.0
  }
}

# ----------------------------------------------------------------------------
# EventBridge Event Bus - Central event routing for SOAR
# ----------------------------------------------------------------------------
resource "aws_cloudwatch_event_bus" "soar" {
  name = "${var.project_name}-soar-events"

  tags = {
    Name        = "${var.project_name}-soar-eventbus"
    Environment = var.environment
    Purpose     = "SOAR"
  }
}

# Archive all events for 7 days (for debugging/audit)
resource "aws_cloudwatch_event_archive" "soar" {
  name             = "${var.project_name}-soar-archive"
  event_source_arn = aws_cloudwatch_event_bus.soar.arn
  retention_days   = 7

  description = "Archive all SOAR events for debugging"
}

# ----------------------------------------------------------------------------
# SQS Queues - Buffer events before Lambda processing
# ----------------------------------------------------------------------------

# Dead Letter Queue - For failed Lambda processing
resource "aws_sqs_queue" "soar_dlq" {
  name                      = "${var.project_name}-soar-dlq"
  message_retention_seconds = 1209600 # 14 days

  tags = {
    Name        = "${var.project_name}-soar-dlq"
    Environment = var.environment
    Purpose     = "SOAR"
  }
}

# Main Queue for high-priority events (critical, high)
resource "aws_sqs_queue" "soar_high_priority" {
  name                       = "${var.project_name}-soar-high-priority"
  delay_seconds              = 0
  max_message_size           = 262144 # 256 KB
  message_retention_seconds  = 345600 # 4 days
  receive_wait_time_seconds  = 10     # Long polling
  visibility_timeout_seconds = 300    # 5 minutes

  redrive_policy = jsonencode({
    deadLetterTargetArn = aws_sqs_queue.soar_dlq.arn
    maxReceiveCount     = 3
  })

  tags = {
    Name        = "${var.project_name}-soar-high-priority"
    Environment = var.environment
    Purpose     = "SOAR"
  }
}

# Queue for medium-priority events
resource "aws_sqs_queue" "soar_medium_priority" {
  name                       = "${var.project_name}-soar-medium-priority"
  delay_seconds              = 0
  max_message_size           = 262144
  message_retention_seconds  = 345600
  receive_wait_time_seconds  = 10
  visibility_timeout_seconds = 300

  redrive_policy = jsonencode({
    deadLetterTargetArn = aws_sqs_queue.soar_dlq.arn
    maxReceiveCount     = 3
  })

  tags = {
    Name        = "${var.project_name}-soar-medium-priority"
    Environment = var.environment
    Purpose     = "SOAR"
  }
}

# Queue for low-priority events (info, debug)
resource "aws_sqs_queue" "soar_low_priority" {
  name                       = "${var.project_name}-soar-low-priority"
  delay_seconds              = 0
  max_message_size           = 262144
  message_retention_seconds  = 345600
  receive_wait_time_seconds  = 10
  visibility_timeout_seconds = 300

  redrive_policy = jsonencode({
    deadLetterTargetArn = aws_sqs_queue.soar_dlq.arn
    maxReceiveCount     = 3
  })

  tags = {
    Name        = "${var.project_name}-soar-low-priority"
    Environment = var.environment
    Purpose     = "SOAR"
  }
}

# ----------------------------------------------------------------------------
# EventBridge Rules - Route events to SQS based on priority
# ----------------------------------------------------------------------------

# Rule for high-priority events (critical, high)
resource "aws_cloudwatch_event_rule" "soar_high_priority" {
  name           = "${var.project_name}-soar-high-priority"
  description    = "Route high-priority security events to SQS"
  event_bus_name = aws_cloudwatch_event_bus.soar.name

  event_pattern = jsonencode({
    detail-type = ["SecurityEvent"]
    detail = {
      severity = ["critical", "high"]
    }
  })

  tags = {
    Name        = "${var.project_name}-soar-high-priority-rule"
    Environment = var.environment
  }
}

resource "aws_cloudwatch_event_target" "soar_high_priority" {
  rule           = aws_cloudwatch_event_rule.soar_high_priority.name
  event_bus_name = aws_cloudwatch_event_bus.soar.name
  target_id      = "HighPrioritySQS"
  arn            = aws_sqs_queue.soar_high_priority.arn
}

# Rule for medium-priority events
resource "aws_cloudwatch_event_rule" "soar_medium_priority" {
  name           = "${var.project_name}-soar-medium-priority"
  description    = "Route medium-priority security events to SQS"
  event_bus_name = aws_cloudwatch_event_bus.soar.name

  event_pattern = jsonencode({
    detail-type = ["SecurityEvent"]
    detail = {
      severity = ["medium"]
    }
  })

  tags = {
    Name        = "${var.project_name}-soar-medium-priority-rule"
    Environment = var.environment
  }
}

resource "aws_cloudwatch_event_target" "soar_medium_priority" {
  rule           = aws_cloudwatch_event_rule.soar_medium_priority.name
  event_bus_name = aws_cloudwatch_event_bus.soar.name
  target_id      = "MediumPrioritySQS"
  arn            = aws_sqs_queue.soar_medium_priority.arn
}

# Rule for low-priority events
resource "aws_cloudwatch_event_rule" "soar_low_priority" {
  name           = "${var.project_name}-soar-low-priority"
  description    = "Route low-priority security events to SQS"
  event_bus_name = aws_cloudwatch_event_bus.soar.name

  event_pattern = jsonencode({
    detail-type = ["SecurityEvent"]
    detail = {
      severity = ["low", "info"]
    }
  })

  tags = {
    Name        = "${var.project_name}-soar-low-priority-rule"
    Environment = var.environment
  }
}

resource "aws_cloudwatch_event_target" "soar_low_priority" {
  rule           = aws_cloudwatch_event_rule.soar_low_priority.name
  event_bus_name = aws_cloudwatch_event_bus.soar.name
  target_id      = "LowPrioritySQS"
  arn            = aws_sqs_queue.soar_low_priority.arn
}

# ----------------------------------------------------------------------------
# SQS Queue Policies - Allow EventBridge to send messages
# ----------------------------------------------------------------------------
resource "aws_sqs_queue_policy" "soar_high_priority" {
  queue_url = aws_sqs_queue.soar_high_priority.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        Service = "events.amazonaws.com"
      }
      Action   = "sqs:SendMessage"
      Resource = aws_sqs_queue.soar_high_priority.arn
      Condition = {
        ArnEquals = {
          "aws:SourceArn" = aws_cloudwatch_event_rule.soar_high_priority.arn
        }
      }
    }]
  })
}

resource "aws_sqs_queue_policy" "soar_medium_priority" {
  queue_url = aws_sqs_queue.soar_medium_priority.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        Service = "events.amazonaws.com"
      }
      Action   = "sqs:SendMessage"
      Resource = aws_sqs_queue.soar_medium_priority.arn
      Condition = {
        ArnEquals = {
          "aws:SourceArn" = aws_cloudwatch_event_rule.soar_medium_priority.arn
        }
      }
    }]
  })
}

resource "aws_sqs_queue_policy" "soar_low_priority" {
  queue_url = aws_sqs_queue.soar_low_priority.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        Service = "events.amazonaws.com"
      }
      Action   = "sqs:SendMessage"
      Resource = aws_sqs_queue.soar_low_priority.arn
      Condition = {
        ArnEquals = {
          "aws:SourceArn" = aws_cloudwatch_event_rule.soar_low_priority.arn
        }
      }
    }]
  })
}

# ----------------------------------------------------------------------------
# CloudWatch Alarms - Monitor SOAR system health
# ----------------------------------------------------------------------------

# Alarm for ECS Service CPU
resource "aws_cloudwatch_metric_alarm" "soar_cpu_high" {
  alarm_name          = "${var.project_name}-soar-cpu-high"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "2"
  metric_name         = "CPUUtilization"
  namespace           = "AWS/ECS"
  period              = "300"
  statistic           = "Average"
  threshold           = "80"
  alarm_description   = "SOAR ECS service CPU utilization is too high"

  dimensions = {
    ClusterName = aws_ecs_cluster.soar.name
    ServiceName = aws_ecs_service.soar.name
  }

  tags = {
    Name        = "${var.project_name}-soar-cpu-alarm"
    Environment = var.environment
  }
}

# Alarm for SQS Queue Depth (high priority)
resource "aws_cloudwatch_metric_alarm" "soar_queue_depth" {
  alarm_name          = "${var.project_name}-soar-queue-depth"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "1"
  metric_name         = "ApproximateNumberOfMessagesVisible"
  namespace           = "AWS/SQS"
  period              = "300"
  statistic           = "Average"
  threshold           = "100"
  alarm_description   = "SOAR high-priority queue has too many messages"

  dimensions = {
    QueueName = aws_sqs_queue.soar_high_priority.name
  }

  tags = {
    Name        = "${var.project_name}-soar-queue-alarm"
    Environment = var.environment
  }
}

# Alarm for Dead Letter Queue
resource "aws_cloudwatch_metric_alarm" "soar_dlq" {
  alarm_name          = "${var.project_name}-soar-dlq-messages"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "1"
  metric_name         = "ApproximateNumberOfMessagesVisible"
  namespace           = "AWS/SQS"
  period              = "60"
  statistic           = "Average"
  threshold           = "0"
  alarm_description   = "Messages in SOAR DLQ - Lambda processing failures"

  dimensions = {
    QueueName = aws_sqs_queue.soar_dlq.name
  }

  tags = {
    Name        = "${var.project_name}-soar-dlq-alarm"
    Environment = var.environment
  }
}
