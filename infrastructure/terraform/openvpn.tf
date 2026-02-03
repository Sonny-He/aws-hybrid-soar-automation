# Security Group for OpenVPN Server
resource "aws_security_group" "openvpn" {
  name_prefix = "${var.project_name}-openvpn-"
  vpc_id      = aws_vpc.main.id

  # OpenVPN port
  ingress {
    from_port   = 1194
    to_port     = 1194
    protocol    = "udp"
    cidr_blocks = ["0.0.0.0/0"]
    description = "OpenVPN access"
  }

  # SSH access
  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
    description = "SSH management"
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name        = "${var.project_name}-openvpn-sg"
    Environment = var.environment
  }
}

# OpenVPN Server Instance
resource "aws_instance" "openvpn" {
  ami           = data.aws_ami.amazon_linux.id
  instance_type = "t3.micro"
  subnet_id     = aws_subnet.public[1].id
  key_name      = var.ssh_key_name

  vpc_security_group_ids = [aws_security_group.openvpn.id]
  source_dest_check      = false

  user_data = base64encode(templatefile("${path.module}/openvpn_user_data.sh", {
    vpc_cidr        = "10.0.0.0/16"
    vpn_client_cidr = "10.8.0.0/24"
    eip_address     = aws_eip.openvpn.public_ip
  }))

  # CRITICAL: Prevent replacement on AMI/user_data changes
  lifecycle {
    ignore_changes = [ami, user_data]
  }

  tags = {
    Name        = "${var.project_name}-openvpn"
    Environment = var.environment
    Purpose     = "VPN"
  }
}

# VPN Client Routes - Allow VPN clients (10.8.0.0/24) to reach all subnets
# These routes tell each subnet how to send RETURN traffic back to VPN clients

# Route VPN clients through OpenVPN server - PUBLIC subnets
resource "aws_route" "vpn_public" {
  route_table_id         = aws_route_table.public.id
  destination_cidr_block = "10.8.0.0/24"
  network_interface_id   = aws_instance.openvpn.primary_network_interface_id

  lifecycle {
    create_before_destroy = true
  }
}

# Route VPN clients through OpenVPN server - PRIVATE subnets
resource "aws_route" "vpn_private" {
  route_table_id         = aws_route_table.private.id
  destination_cidr_block = "10.8.0.0/24"
  network_interface_id   = aws_instance.openvpn.primary_network_interface_id

  lifecycle {
    create_before_destroy = true
  }
}

# Route VPN clients through OpenVPN server - DATABASE subnets
resource "aws_route" "vpn_database" {
  route_table_id         = aws_route_table.database.id
  destination_cidr_block = "10.8.0.0/24"
  network_interface_id   = aws_instance.openvpn.primary_network_interface_id

  lifecycle {
    create_before_destroy = true
  }
}

# Elastic IP for OpenVPN
resource "aws_eip" "openvpn" {
  domain = "vpc"

  tags = {
    Name        = "${var.project_name}-openvpn-eip"
    Environment = var.environment
  }
}

resource "aws_eip_association" "openvpn" {
  instance_id   = aws_instance.openvpn.id
  allocation_id = aws_eip.openvpn.id
}