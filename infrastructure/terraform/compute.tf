# NAT Instance (single instance in AZ-a for cost optimization)
resource "aws_instance" "nat_instance" {
  ami                    = data.aws_ami.amazon_linux.id
  instance_type          = "t3.nano"
  subnet_id              = aws_subnet.public[0].id
  vpc_security_group_ids = [aws_security_group.nat_instance.id]
  key_name               = var.ssh_key_name # Fixed key consistency

  source_dest_check = false

  user_data = base64encode(file("${path.module}/nat_user_data.sh"))

  lifecycle {
    ignore_changes = [ami, user_data]
  }

  tags = {
    Name        = "${var.project_name}-nat-instance"
    Environment = var.environment
    Purpose     = "NAT"
  }
}

# Launch Template for Web Servers
resource "aws_launch_template" "web" {
  name_prefix   = "${var.project_name}-web-"
  image_id      = data.aws_ami.amazon_linux.id
  instance_type = "t3.micro"
  key_name      = var.ssh_key_name # Fixed key consistency

  vpc_security_group_ids = [aws_security_group.webservers.id]

  user_data = base64encode(templatefile("${path.module}/web_user_data.sh", {
    db_endpoint = aws_db_instance.main.endpoint
  }))

  tag_specifications {
    resource_type = "instance"
    tags = {
      Name        = "${var.project_name}-webserver"
      Environment = var.environment
    }
  }

  # Enable detailed monitoring for auto-scaling
  monitoring {
    enabled = true
  }
}

# Auto Scaling Group (spans both AZs)
resource "aws_autoscaling_group" "web" {
  name                      = "${var.project_name}-web-asg"
  vpc_zone_identifier       = aws_subnet.private_web[*].id
  target_group_arns         = [aws_lb_target_group.web.arn]
  health_check_type         = "ELB"
  health_check_grace_period = 900 # Change from 300

  min_size         = 2
  max_size         = 10
  desired_capacity = 2

  # Cost optimization: use mixed instance types with Spot instances
  mixed_instances_policy {
    instances_distribution {
      on_demand_base_capacity                  = 1
      on_demand_percentage_above_base_capacity = 25
      spot_allocation_strategy                 = "capacity-optimized"
    }

    launch_template {
      launch_template_specification {
        launch_template_id = aws_launch_template.web.id
        version            = "$Latest"
      }

      override {
        instance_type = "t3.micro"
      }

      override {
        instance_type = "t3.small"
      }
    }
  }

  tag {
    key                 = "Name"
    value               = "${var.project_name}-webserver-asg"
    propagate_at_launch = false
  }

  tag {
    key                 = "Environment"
    value               = var.environment
    propagate_at_launch = true
  }

  depends_on = [aws_db_instance.main]
}

# Auto Scaling Policies
resource "aws_autoscaling_policy" "scale_up" {
  name                   = "${var.project_name}-scale-up"
  scaling_adjustment     = 2
  adjustment_type        = "ChangeInCapacity"
  cooldown               = 300
  autoscaling_group_name = aws_autoscaling_group.web.name
}

resource "aws_autoscaling_policy" "scale_down" {
  name                   = "${var.project_name}-scale-down"
  scaling_adjustment     = -1
  adjustment_type        = "ChangeInCapacity"
  cooldown               = 300
  autoscaling_group_name = aws_autoscaling_group.web.name
}