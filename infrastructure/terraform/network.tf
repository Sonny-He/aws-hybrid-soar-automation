# VPC
resource "aws_vpc" "main" {
  cidr_block           = "10.0.0.0/16"
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = {
    Name        = "${var.project_name}-vpc"
    Environment = var.environment
  }
}

# Internet Gateway
resource "aws_internet_gateway" "main" {
  vpc_id = aws_vpc.main.id

  tags = {
    Name        = "${var.project_name}-igw"
    Environment = var.environment
  }
}

# Public Subnets (both AZs for ALB)
resource "aws_subnet" "public" {
  count                   = 2
  vpc_id                  = aws_vpc.main.id
  cidr_block              = "10.0.${count.index + 1}.0/24"
  availability_zone       = data.aws_availability_zones.available.names[count.index]
  map_public_ip_on_launch = true

  tags = {
    Name        = "${var.project_name}-public-${count.index + 1}"
    Environment = var.environment
    Type        = "Public"
    AZ          = data.aws_availability_zones.available.names[count.index]
  }
}

# Private Subnets for Web Servers (both AZs)
resource "aws_subnet" "private_web" {
  count             = 2
  vpc_id            = aws_vpc.main.id
  cidr_block        = "10.0.${count.index + 10}.0/24"
  availability_zone = data.aws_availability_zones.available.names[count.index]

  tags = {
    Name        = "${var.project_name}-private-web-${count.index + 1}"
    Environment = var.environment
    Type        = "Private"
    Purpose     = "Web"
    AZ          = data.aws_availability_zones.available.names[count.index]
  }
}

# Database Subnets (both AZs - required for RDS)
resource "aws_subnet" "database" {
  count             = 2
  vpc_id            = aws_vpc.main.id
  cidr_block        = "10.0.${count.index + 20}.0/24"
  availability_zone = data.aws_availability_zones.available.names[count.index]

  tags = {
    Name        = "${var.project_name}-database-${count.index + 1}"
    Environment = var.environment
    Type        = "Database"
    AZ          = data.aws_availability_zones.available.names[count.index]
  }
}

# Monitoring Subnet (Private with NAT access)
resource "aws_subnet" "monitoring_private" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = "10.0.30.0/24"
  availability_zone = data.aws_availability_zones.available.names[0]

  tags = {
    Name        = "${var.project_name}-monitoring"
    Environment = var.environment
    Type        = "Private"
    Purpose     = "Monitoring"
  }
}

# Route Tables
resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.main.id
  }

  tags = {
    Name        = "${var.project_name}-public-rt"
    Environment = var.environment
  }
}

# Private route table - routes through NAT instance
# Used by: web servers AND monitoring subnet
resource "aws_route_table" "private" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block           = "0.0.0.0/0"
    network_interface_id = aws_instance.nat_instance.primary_network_interface_id
  }

  tags = {
    Name        = "${var.project_name}-private-rt"
    Environment = var.environment
  }
}

# Route VPN client traffic back through OpenVPN server
resource "aws_route" "vpn_to_private" {
  route_table_id         = aws_route_table.private.id
  destination_cidr_block = "10.8.0.0/24"
  network_interface_id   = aws_instance.openvpn.primary_network_interface_id

  # Ensure OpenVPN instance exists before creating this route
  depends_on = [aws_instance.openvpn]
}

# Database route table (no internet access)
resource "aws_route_table" "database" {
  vpc_id = aws_vpc.main.id

  tags = {
    Name        = "${var.project_name}-database-rt"
    Environment = var.environment
  }
}

# Route Table Associations
resource "aws_route_table_association" "public" {
  count          = length(aws_subnet.public)
  subnet_id      = aws_subnet.public[count.index].id
  route_table_id = aws_route_table.public.id
}

resource "aws_route_table_association" "private_web" {
  count          = length(aws_subnet.private_web)
  subnet_id      = aws_subnet.private_web[count.index].id
  route_table_id = aws_route_table.private.id
}

resource "aws_route_table_association" "database" {
  count          = length(aws_subnet.database)
  subnet_id      = aws_subnet.database[count.index].id
  route_table_id = aws_route_table.database.id
}

# Monitoring subnet uses the same private route table (routes through NAT)
resource "aws_route_table_association" "monitoring" {
  subnet_id      = aws_subnet.monitoring_private.id
  route_table_id = aws_route_table.private.id
}