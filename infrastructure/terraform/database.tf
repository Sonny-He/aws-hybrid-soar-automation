# Database Subnet Group
resource "aws_db_subnet_group" "main" {
  name       = "${var.project_name}-db-subnet-group"
  subnet_ids = aws_subnet.database[*].id

  tags = {
    Name        = "${var.project_name}-db-subnet-group"
    Environment = var.environment
  }
}

# RDS Database
resource "aws_db_instance" "main" {
  identifier = "${var.project_name}-database"

  engine         = "mysql"
  engine_version = "8.0"
  instance_class = "db.t3.micro"

  allocated_storage     = 20
  max_allocated_storage = 100
  storage_type          = "gp2"
  storage_encrypted     = true

  db_name  = "webapp"
  username = "admin"
  password = "ChangeMe123!" # Use AWS Secrets Manager in production

  vpc_security_group_ids = [aws_security_group.database.id]
  db_subnet_group_name   = aws_db_subnet_group.main.name

  # Single AZ for cost optimization
  multi_az          = false
  availability_zone = data.aws_availability_zones.available.names[0]

  backup_retention_period = 7
  backup_window           = "03:00-04:00"
  maintenance_window      = "sun:04:00-sun:05:00"

  skip_final_snapshot = true
  deletion_protection = false

  tags = {
    Name        = "${var.project_name}-database"
    Environment = var.environment
  }
}

# ADD THIS NEW RESOURCE
resource "aws_db_parameter_group" "main" {
  name   = "${var.project_name}-mysql8-params"
  family = "mysql8.0"

  parameter {
    name  = "character_set_server"
    value = "utf8"
  }

  parameter {
    name  = "collation_server"
    value = "utf8_general_ci"
  }

  tags = {
    Name        = "${var.project_name}-db-params"
    Environment = var.environment
  }
}

# Wait for RDS to be fully available
resource "null_resource" "wait_for_rds" {
  depends_on = [aws_db_instance.main]

  provisioner "local-exec" {
    command = <<-EOF
      echo "Waiting for RDS instance to be available..."
      aws rds wait db-instance-available --db-instance-identifier ${aws_db_instance.main.identifier} --region ${var.aws_region}
      echo "RDS instance is now available!"
    EOF
  }

  triggers = {
    rds_id = aws_db_instance.main.id
  }
}

# Test database connectivity from NAT instance (optional - for debugging)
resource "null_resource" "database_connectivity_test" {
  depends_on = [
    null_resource.wait_for_rds,
    aws_instance.nat_instance
  ]

  # Only run if we want to test connectivity (can be disabled)
  count = var.enable_db_connectivity_test ? 1 : 0

  provisioner "remote-exec" {
    inline = [
      "echo 'Testing database connectivity from NAT instance...'",
      "sudo yum install -y mysql",
      "mysql -h ${aws_db_instance.main.address} -u admin -pChangeMe123! -e 'SELECT VERSION();' || echo 'Connection test failed - this is normal if RDS is still initializing'",
      "echo 'Database connectivity test completed'"
    ]

    connection {
      type        = "ssh"
      user        = "ec2-user"
      host        = aws_instance.nat_instance.public_ip
      private_key = file(var.ssh_private_key_path)
      timeout     = "5m"
    }
  }

  triggers = {
    rds_endpoint = aws_db_instance.main.endpoint
    always_run   = timestamp()
  }
}

# Database status check (data source to verify RDS is ready)
data "aws_db_instance" "main_status" {
  depends_on             = [null_resource.wait_for_rds]
  db_instance_identifier = aws_db_instance.main.identifier
}

# CloudWatch Log Group for RDS (optional - for better monitoring)
resource "aws_cloudwatch_log_group" "rds_error" {
  name              = "/aws/rds/instance/${aws_db_instance.main.identifier}/error"
  retention_in_days = 7

  tags = {
    Name        = "${var.project_name}-rds-error-logs"
    Environment = var.environment
  }
}

resource "aws_cloudwatch_log_group" "rds_general" {
  name              = "/aws/rds/instance/${aws_db_instance.main.identifier}/general"
  retention_in_days = 7

  tags = {
    Name        = "${var.project_name}-rds-general-logs"
    Environment = var.environment
  }
}

resource "aws_cloudwatch_log_group" "rds_slowquery" {
  name              = "/aws/rds/instance/${aws_db_instance.main.identifier}/slowquery"
  retention_in_days = 7

  tags = {
    Name        = "${var.project_name}-rds-slowquery-logs"
    Environment = var.environment
  }
}