# IAM Role for Monitoring Server (CloudWatch access)
resource "aws_iam_role" "monitoring" {
  name = "${var.project_name}-monitoring-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "ec2.amazonaws.com"
        }
      }
    ]
  })

  tags = {
    Name        = "${var.project_name}-monitoring-role"
    Environment = var.environment
  }
}

# IAM Policy for CloudWatch read access
resource "aws_iam_policy" "monitoring_cloudwatch" {
  name        = "${var.project_name}-monitoring-cloudwatch"
  description = "CloudWatch read access for monitoring server"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "cloudwatch:GetMetricStatistics",
          "cloudwatch:ListMetrics",
          "cloudwatch:GetMetricData",
          "ec2:DescribeInstances",
          "ec2:DescribeRegions",
          "rds:DescribeDBInstances",
          "elasticloadbalancing:DescribeLoadBalancers",
          "autoscaling:DescribeAutoScalingGroups",
          "logs:DescribeLogGroups",
          "logs:DescribeLogStreams",
          "logs:GetLogEvents",
          "logs:FilterLogEvents",
          "logs:StartQuery",
          "logs:GetQueryResults",
          "logs:StopQuery"
        ]
        Resource = "*"
      }
    ]
  })

  tags = {
    Name        = "${var.project_name}-monitoring-cloudwatch-policy"
    Environment = var.environment
  }
}

# Attach policy to role
resource "aws_iam_role_policy_attachment" "monitoring_cloudwatch" {
  policy_arn = aws_iam_policy.monitoring_cloudwatch.arn
  role       = aws_iam_role.monitoring.name
}

# Instance profile for the monitoring server
resource "aws_iam_instance_profile" "monitoring" {
  name = "${var.project_name}-monitoring-profile"
  role = aws_iam_role.monitoring.name

  tags = {
    Name        = "${var.project_name}-monitoring-profile"
    Environment = var.environment
  }
}

# Security Group for Monitoring Server
resource "aws_security_group" "monitoring" {
  name_prefix = "${var.project_name}-monitoring-"
  vpc_id      = aws_vpc.main.id

  # SSH directly from VPN clients
  ingress {
    description = "SSH from VPN clients"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["10.8.0.0/24"]
  }

  # Grafana Web UI
  ingress {
    from_port   = 3000
    to_port     = 3000
    protocol    = "tcp"
    cidr_blocks = ["10.8.0.0/24"] # VPN clients only
    description = "Grafana UI access via VPN"
  }

  # Prometheus Web UI (optional - for debugging)
  ingress {
    from_port   = 9090
    to_port     = 9090
    protocol    = "tcp"
    cidr_blocks = ["10.8.0.0/24"] # VPN clients only
    description = "Prometheus UI access via VPN"
  }

  # SSH from NAT instance
  ingress {
    from_port       = 22
    to_port         = 22
    protocol        = "tcp"
    security_groups = [aws_security_group.nat_instance.id]
    description     = "SSH access from NAT instance"
  }

  # Allow traffic from OpenVPN server for VPN packet forwarding
  ingress {
    from_port       = 0
    to_port         = 0
    protocol        = "-1"
    security_groups = [aws_security_group.openvpn.id]
    description     = "Allow all traffic from OpenVPN server for VPN forwarding"
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name        = "${var.project_name}-monitoring-sg"
    Environment = var.environment
  }
}

# Monitoring Server Instance (Prometheus + Grafana + Loki)
resource "aws_instance" "monitoring" {
  ami           = data.aws_ami.amazon_linux.id
  instance_type = "t3.small" # Slightly larger for monitoring workload
  subnet_id     = aws_subnet.monitoring_private.id
  key_name      = var.ssh_key_name # Fixed key consistency

  vpc_security_group_ids = [aws_security_group.monitoring.id]
  iam_instance_profile   = aws_iam_instance_profile.monitoring.name # THIS IS THE KEY LINE

  user_data = base64encode(templatefile("${path.module}/monitoring_user_data.sh", {
    vpc_cidr        = aws_vpc.main.cidr_block
    web_subnet_1    = aws_subnet.private_web[0].cidr_block
    web_subnet_2    = aws_subnet.private_web[1].cidr_block
    nat_instance_ip = aws_instance.nat_instance.private_ip
    db_identifier   = aws_db_instance.main.identifier
    aws_region      = var.aws_region
  }))

  lifecycle {
    ignore_changes = [ami, user_data]
  }

  tags = {
    Name        = "${var.project_name}-monitoring"
    Environment = var.environment
    Purpose     = "Monitoring"
    Services    = "Prometheus-Grafana-Loki"
  }

  # Ensure monitoring starts after other infrastructure AND NAT is ready
  depends_on = [
    aws_instance.nat_instance,
    aws_route_table.private,
    aws_route_table_association.monitoring,
    aws_autoscaling_group.web,
    aws_db_instance.main,
    aws_iam_instance_profile.monitoring
  ]
}

# CloudWatch Log Group for monitoring server logs
resource "aws_cloudwatch_log_group" "monitoring" {
  name              = "/aws/ec2/${var.project_name}-monitoring"
  retention_in_days = var.cloudwatch_logs_retention

  tags = {
    Name        = "${var.project_name}-monitoring-logs"
    Environment = var.environment
  }
}