#!/bin/bash

# Update system
yum update -y

# Enable IP forwarding
echo 'net.ipv4.ip_forward = 1' >> /etc/sysctl.conf
sysctl -p

# Configure iptables for NAT
iptables -t nat -A POSTROUTING -o eth0 -j MASQUERADE
iptables -A FORWARD -i eth0 -o eth0 -m state --state RELATED,ESTABLISHED -j ACCEPT
iptables -A FORWARD -i eth0 -o eth0 -j ACCEPT

# Save iptables rules
service iptables save

# Make iptables rules persistent
chkconfig iptables on

# Install CloudWatch agent for monitoring
wget https://s3.amazonaws.com/amazoncloudwatch-agent/amazon_linux/amd64/latest/amazon-cloudwatch-agent.rpm
rpm -U ./amazon-cloudwatch-agent.rpm

# Create CloudWatch config for NAT monitoring
cat > /opt/aws/amazon-cloudwatch-agent/etc/amazon-cloudwatch-agent.json << 'EOF'
{
    "metrics": {
        "namespace": "CWAgent",
        "metrics_collected": {
            "cpu": {
                "measurement": [
                    "cpu_usage_idle",
                    "cpu_usage_user",
                    "cpu_usage_system"
                ],
                "metrics_collection_interval": 60
            },
            "disk": {
                "measurement": [
                    "used_percent"
                ],
                "metrics_collection_interval": 60,
                "resources": [
                    "*"
                ]
            },
            "mem": {
                "measurement": [
                    "mem_used_percent"
                ],
                "metrics_collection_interval": 60
            },
            "netstat": {
                "measurement": [
                    "tcp_established",
                    "tcp_time_wait"
                ],
                "metrics_collection_interval": 60
            }
        }
    },
    "logs": {
        "logs_collected": {
            "files": {
                "collect_list": [
                    {
                        "file_path": "/var/log/messages",
                        "log_group_name": "cs1-ma-nca-nat-messages",
                        "log_stream_name": "{instance_id}"
                    }
                ]
            }
        }
    }
}
EOF

# Start CloudWatch agent
/opt/aws/amazon-cloudwatch-agent/bin/amazon-cloudwatch-agent-ctl -a fetch-config -m ec2 -c file:/opt/aws/amazon-cloudwatch-agent/etc/amazon-cloudwatch-agent.json -s

# Create a simple status page (accessible via SSH)
cat > /home/ec2-user/nat-status.sh << 'EOF'
#!/bin/bash
echo "=== NAT Instance Status ==="
echo "Hostname: $(hostname)"
echo "Private IP: $(curl -s http://169.254.169.254/latest/meta-data/local-ipv4)"
echo "Public IP: $(curl -s http://169.254.169.254/latest/meta-data/public-ipv4)"
echo ""
echo "=== Network Traffic ==="
iptables -t nat -L -n -v
echo ""
echo "=== Active Connections ==="
netstat -nat | grep ESTABLISHED | wc -l
echo " active connections"
echo ""
echo "=== System Resources ==="
free -h
echo ""
df -h
EOF

chmod +x /home/ec2-user/nat-status.sh

# Install htop for easier monitoring
yum install -y htop

# Log completion
echo "NAT instance setup completed at $(date)" >> /home/ec2-user/setup.log

# Optional: Create a simple web server for health checks (port 8080)
yum install -y python3
cat > /home/ec2-user/health-server.py << 'EOF'
#!/usr/bin/env python3
import http.server
import socketserver
import json
import subprocess
from datetime import datetime

class HealthHandler(http.server.SimpleHTTPRequestHandler):
    def do_GET(self):
        if self.path == '/health':
            self.send_response(200)
            self.send_header('Content-type', 'application/json')
            self.end_headers()
            
            # Get system stats
            with open('/proc/loadavg', 'r') as f:
                load_avg = f.read().strip().split()[0]
            
            # Get active connections
            result = subprocess.run(['netstat', '-nat'], capture_output=True, text=True)
            connections = len([line for line in result.stdout.split('\n') if 'ESTABLISHED' in line])
            
            health_data = {
                "status": "healthy",
                "timestamp": datetime.now().isoformat(),
                "load_average": float(load_avg),
                "active_connections": connections,
                "service": "nat-instance"
            }
            
            self.wfile.write(json.dumps(health_data, indent=2).encode())
        else:
            super().do_GET()

# Start health server in background
nohup python3 -c "
import http.server
import socketserver
from health_handler import HealthHandler

PORT = 8080
with socketserver.TCPServer(('', PORT), HealthHandler) as httpd:
    print(f'Health server running on port {PORT}')
    httpd.serve_forever()
" > /var/log/health-server.log 2>&1 &
EOF

# Install Node Exporter for Prometheus monitoring
{
    echo "Installing Node Exporter for monitoring..." >> /home/ec2-user/setup.log
    
    # Download and install Node Exporter
    cd /opt
    wget https://github.com/prometheus/node_exporter/releases/download/v1.6.1/node_exporter-1.6.1.linux-amd64.tar.gz
    tar xvf node_exporter-1.6.1.linux-amd64.tar.gz
    mv node_exporter-1.6.1.linux-amd64/node_exporter /usr/local/bin/
    rm -rf node_exporter-1.6.1.linux-amd64*
    
    # Create node_exporter user
    useradd --no-create-home --shell /bin/false node_exporter
    chown node_exporter:node_exporter /usr/local/bin/node_exporter
    
    # Create systemd service
    cat > /etc/systemd/system/node_exporter.service << 'EOF'
[Unit]
Description=Node Exporter
Wants=network-online.target
After=network-online.target

[Service]
User=node_exporter
Group=node_exporter
Type=simple
ExecStart=/usr/local/bin/node_exporter --collector.systemd --collector.processes

[Install]
WantedBy=multi-user.target
EOF
    
    # Start and enable Node Exporter
    systemctl daemon-reload
    systemctl start node_exporter
    systemctl enable node_exporter
    
    if systemctl is-active --quiet node_exporter; then
        echo "Node Exporter started successfully on port 9100" >> /home/ec2-user/setup.log
    else
        echo "ERROR: Node Exporter failed to start" >> /home/ec2-user/setup.log
        systemctl status node_exporter >> /home/ec2-user/setup.log
    fi
} &

echo "NAT Instance configured successfully!"