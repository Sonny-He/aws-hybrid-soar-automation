# Outputs
output "load_balancer_dns" {
  description = "DNS name of the Application Load Balancer"
  value       = aws_lb.main.dns_name
}

output "database_endpoint" {
  description = "RDS instance endpoint"
  value       = aws_db_instance.main.endpoint
  sensitive   = true
}

output "nat_instance_ip" {
  description = "Public IP of NAT instance (for SSH access)"
  value       = aws_instance.nat_instance.public_ip
}

output "cloudwatch_dashboard_url" {
  description = "CloudWatch Dashboard URL"
  value       = "https://${var.aws_region}.console.aws.amazon.com/cloudwatch/home?region=${var.aws_region}#dashboards:name=${aws_cloudwatch_dashboard.main.dashboard_name}"
}

output "openvpn_server_ip" {
  description = "Public IP of OpenVPN server (Elastic IP - stable)"
  value       = aws_eip.openvpn.public_ip
}

output "openvpn_scp_command" {
  description = "SCP command to download OpenVPN client configuration"
  value       = "scp -i ~/.ssh/aws-cs1-key ec2-user@${aws_eip.openvpn.public_ip}:client.ovpn C:/Users/sonny/cs1-ma-nca-infrastructure/"
}

output "monitoring_server_ip" {
  description = "Private IP of monitoring server (access via VPN)"
  value       = aws_instance.monitoring.private_ip
}

output "monitoring_access_info" {
  description = "How to access monitoring services (requires VPN connection)"
  value = {
    grafana_url         = "http://${aws_instance.monitoring.private_ip}:3000"
    prometheus_url      = "http://${aws_instance.monitoring.private_ip}:9090"
    loki_url            = "http://${aws_instance.monitoring.private_ip}:3100"
    grafana_credentials = "admin / admin123"
    access_method       = "Connect via OpenVPN first"
  }
}

output "vpn_access_info" {
  description = "How to connect to VPN and access private resources"
  value = {
    server_ip            = aws_eip.openvpn.public_ip # ← FIXED
    port                 = 1194
    protocol             = "UDP"
    scp_download_command = "scp -i ~/.ssh/aws-cs1-key ec2-user@${aws_eip.openvpn.public_ip}:client.ovpn C:/Users/sonny/cs1-ma-nca-infrastructure" # ← FIXED
    vpn_network          = "10.8.0.0/24"
    vpc_access           = "10.0.0.0/16"
  }
}

# Route 53 Private Hosted Zone Outputs

output "private_dns_zone" {
  description = "Private hosted zone information"
  value = {
    zone_id     = aws_route53_zone.private.zone_id
    domain_name = var.internal_domain_name
    vpc_id      = aws_vpc.main.id
  }
}

output "internal_dns_records" {
  description = "Internal DNS names for private resources (use these instead of IPs)"
  value = {
    database   = "database.${var.internal_domain_name}"
    app        = "app.${var.internal_domain_name}"
    monitoring = "monitoring.${var.internal_domain_name}"
    nat        = "nat.${var.internal_domain_name}"
  }
}