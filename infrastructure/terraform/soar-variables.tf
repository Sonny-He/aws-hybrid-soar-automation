# ============================================================================
# SOAR System Variables - Add to your existing variables.tf
# ============================================================================

# SOAR Email Configuration
variable "soar_alert_email" {
  description = "Email address to receive SOAR alerts"
  type        = string
  default     = "548750@student.fontys.nl"
}

variable "soar_sender_email" {
  description = "Verified SES sender email for SOAR notifications"
  type        = string
  default     = "548750@student.fontys.nl" # CHANGE THIS! (must be verified in SES)
}

# SOAR ECS Configuration
variable "soar_task_cpu" {
  description = "CPU units for SOAR ECS task (256 = 0.25 vCPU, 512 = 0.5 vCPU)"
  type        = number
  default     = 512
}

variable "soar_task_memory" {
  description = "Memory for SOAR ECS task in MB"
  type        = number
  default     = 1024
}

variable "soar_desired_count" {
  description = "Desired number of SOAR ECS tasks (min 2 for HA)"
  type        = number
  default     = 2
}

variable "soar_max_tasks" {
  description = "Maximum number of SOAR ECS tasks for auto-scaling"
  type        = number
  default     = 10
}

# SOAR Queue Configuration
variable "soar_queue_retention_days" {
  description = "Number of days to retain messages in SQS queues"
  type        = number
  default     = 4
}

variable "soar_dlq_retention_days" {
  description = "Number of days to retain messages in Dead Letter Queue"
  type        = number
  default     = 14
}

# SOAR Lambda Configuration
variable "soar_lambda_timeout" {
  description = "Lambda function timeout in seconds"
  type        = number
  default     = 60
}

variable "soar_lambda_memory" {
  description = "Lambda function memory in MB"
  type        = number
  default     = 256
}

# SOAR Storage Configuration
variable "soar_logs_retention_days" {
  description = "Number of days to retain SOAR logs in S3"
  type        = number
  default     = 90
}

variable "enable_soar_system" {
  description = "Enable SOAR system deployment"
  type        = bool
  default     = true
}

variable "soar_enable_insights" {
  description = "Enable Lambda Insights for enhanced monitoring"
  type        = bool
  default     = true
}
