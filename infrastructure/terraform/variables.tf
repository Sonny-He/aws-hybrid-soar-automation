variable "project_name" {
  description = "Name of the project"
  type        = string
  default     = "cs1-ma-nca"
}

variable "environment" {
  description = "Environment name (dev, staging, prod)"
  type        = string
  default     = "dev"
}

variable "aws_region" {
  description = "AWS region"
  type        = string
  default     = "eu-central-1"
}

variable "ssh_key_name" {
  description = "Name of the SSH key pair for EC2 instances"
  type        = string
  default     = "aws-cs1-key" # Change to match your actual AWS key pair name
}

# Network Configuration
variable "vpc_cidr" {
  description = "CIDR block for VPC"
  type        = string
  default     = "10.0.0.0/16"
}

# Instance Configuration
variable "nat_instance_type" {
  description = "EC2 instance type for NAT instance"
  type        = string
  default     = "t3.nano"
}

variable "web_instance_type" {
  description = "EC2 instance type for web servers"
  type        = string
  default     = "t3.micro"
}

# Auto Scaling Configuration
variable "min_size" {
  description = "Minimum number of instances in ASG"
  type        = number
  default     = 2
}

variable "max_size" {
  description = "Maximum number of instances in ASG"
  type        = number
  default     = 10
}

variable "desired_capacity" {
  description = "Desired number of instances in ASG"
  type        = number
  default     = 2
}

# Cost Optimization Settings
variable "spot_percentage" {
  description = "Percentage of Spot instances in ASG (0-100)"
  type        = number
  default     = 75
}

variable "on_demand_base_capacity" {
  description = "Minimum number of On-Demand instances"
  type        = number
  default     = 1
}

# RDS Database Configuration
variable "db_instance_class" {
  description = "RDS instance class"
  type        = string
  default     = "db.t3.micro"
}

variable "db_allocated_storage" {
  description = "Initial allocated storage for RDS (GB)"
  type        = number
  default     = 20
}

variable "db_max_allocated_storage" {
  description = "Maximum allocated storage for RDS auto-scaling (GB)"
  type        = number
  default     = 100
}

variable "db_name" {
  description = "Database name"
  type        = string
  default     = "webapp"
}

variable "db_username" {
  description = "Database username"
  type        = string
  default     = "admin"
}

variable "db_password" {
  description = "Database password (change in production!)"
  type        = string
  default     = "ChangeMe123!"
  sensitive   = true
}

variable "db_multi_az" {
  description = "Enable Multi-AZ for RDS (more expensive but automatic failover)"
  type        = bool
  default     = false
}

variable "db_backup_retention_period" {
  description = "Number of days to retain RDS backups"
  type        = number
  default     = 7
}

# Auto Scaling Thresholds
variable "scale_up_threshold" {
  description = "CPU utilization threshold to scale up (%)"
  type        = number
  default     = 70
}

variable "scale_down_threshold" {
  description = "CPU utilization threshold to scale down (%)"
  type        = number
  default     = 30
}

variable "scale_up_adjustment" {
  description = "Number of instances to add when scaling up"
  type        = number
  default     = 2
}

variable "scale_down_adjustment" {
  description = "Number of instances to remove when scaling down"
  type        = number
  default     = 1
}

variable "scaling_cooldown" {
  description = "Cooldown period between scaling actions (seconds)"
  type        = number
  default     = 300
}

# Monitoring Configuration
variable "enable_detailed_monitoring" {
  description = "Enable detailed CloudWatch monitoring for instances"
  type        = bool
  default     = true
}

variable "cloudwatch_logs_retention" {
  description = "CloudWatch logs retention in days"
  type        = number
  default     = 7
}

# Application Load Balancer Configuration
variable "alb_enable_deletion_protection" {
  description = "Enable deletion protection for Application Load Balancer"
  type        = bool
  default     = false
}

variable "health_check_interval" {
  description = "Health check interval for load balancer targets (seconds)"
  type        = number
  default     = 30
}

variable "health_check_timeout" {
  description = "Health check timeout (seconds)"
  type        = number
  default     = 5
}

variable "health_check_path" {
  description = "Health check path for ALB"
  type        = string
  default     = "/health.php"
}

variable "healthy_threshold" {
  description = "Number of consecutive successful health checks required"
  type        = number
  default     = 2
}

variable "unhealthy_threshold" {
  description = "Number of consecutive failed health checks required"
  type        = number
  default     = 2
}

# Security Configuration
variable "enable_ssh_access" {
  description = "Enable SSH access to NAT instance (for management)"
  type        = bool
  default     = true
}

variable "ssh_allowed_cidr" {
  description = "CIDR block allowed for SSH access to NAT instance"
  type        = string
  default     = "0.0.0.0/0"
}

# Performance Configuration
variable "enable_performance_insights" {
  description = "Enable RDS Performance Insights"
  type        = bool
  default     = true
}

variable "performance_insights_retention_period" {
  description = "Performance Insights retention period (days)"
  type        = number
  default     = 7
}

# Availability Zone Configuration
variable "preferred_az" {
  description = "Preferred availability zone for single-AZ resources"
  type        = string
  default     = "eu-central-1a"
}

# Cost Monitoring
variable "enable_cost_allocation_tags" {
  description = "Enable detailed cost allocation tags"
  type        = bool
  default     = true
}

# Tags
variable "additional_tags" {
  description = "Additional tags to apply to all resources"
  type        = map(string)
  default = {
    Project      = "CS1-MA-NCA"
    Course       = "Cloud Native Architecture"
    University   = "Fontys University"
    Architecture = "Multi-AZ-Cost-Optimized"
    Environment  = "Development"
    CostCenter   = "Education"
    Owner        = "Student"
    Deployment   = "Terraform"
  }
}

# Feature Flags
variable "enable_cloudwatch_dashboard" {
  description = "Create CloudWatch dashboard"
  type        = bool
  default     = true
}

variable "enable_auto_scaling" {
  description = "Enable auto-scaling for web servers"
  type        = bool
  default     = true
}

variable "enable_nat_instance" {
  description = "Use NAT instance instead of NAT Gateway for cost optimization"
  type        = bool
  default     = true
}

variable "enable_spot_instances" {
  description = "Enable Spot instances for cost optimization"
  type        = bool
  default     = true
}

# Advanced Configuration
variable "instance_types" {
  description = "List of instance types for mixed instance policy"
  type        = list(string)
  default     = ["t3.micro", "t3.small"]
}

variable "enable_enhanced_monitoring" {
  description = "Enable enhanced monitoring for RDS"
  type        = bool
  default     = false
}

variable "monitoring_interval" {
  description = "Enhanced monitoring interval for RDS (0, 1, 5, 10, 15, 30, 60)"
  type        = number
  default     = 0
}

variable "enable_db_connectivity_test" {
  description = "Enable database connectivity test from NAT instance"
  type        = bool
  default     = false # Set to true if you want to test connectivity
}

variable "ssh_private_key_path" {
  description = "Path to SSH private key for connecting to instances"
  type        = string
  default     = "C:/Users/sonny/.ssh/aws-cs1-key" # Adjust to your key path
}

variable "internal_domain_name" {
  description = "Internal domain name for private hosted zone (e.g., internal.cs1-ma-nca.local)"
  type        = string
  default     = "internal.cs1-ma-nca.local"
}