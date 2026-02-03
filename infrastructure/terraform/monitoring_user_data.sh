#!/bin/bash

# Wait for internet connectivity before proceeding
wait_for_internet() {
    local max_attempts=60
    local attempt=0
    
    echo "$(date): Waiting for internet connectivity..."
    
    while [ $attempt -lt $max_attempts ]; do
        if curl -s --max-time 5 https://amazonlinux-2-repos-eu-central-1.s3.amazonaws.com >/dev/null 2>&1; then
            echo "$(date): Internet connectivity established"
            return 0
        fi
        
        if curl -s --max-time 5 http://google.com >/dev/null 2>&1; then
            echo "$(date): Internet connectivity established"
            return 0
        fi
        
        attempt=$((attempt + 1))
        echo "$(date): Waiting for internet... attempt $attempt/$max_attempts"
        sleep 10
    done
    
    echo "$(date): ERROR: Failed to establish internet connectivity after $max_attempts attempts"
    return 1
}

# Simple bootstrap script that downloads and runs the full setup
log() {
    echo "$(date): $1" | tee -a /var/log/monitoring-bootstrap.log
}

log "Starting monitoring bootstrap..."

# CRITICAL: Wait for internet before doing anything
wait_for_internet || exit 1

# Update system and install basics
yum update -y
yum install -y docker git awscli curl

# Start Docker
systemctl start docker
systemctl enable docker
usermod -a -G docker ec2-user

# Create monitoring directories
mkdir -p /opt/monitoring/{config/{prometheus,grafana,loki},prometheus,grafana,loki}
mkdir -p /var/lib/{prometheus,grafana,loki}

LOCAL_IP=$(curl -s http://169.254.169.254/latest/meta-data/local-ipv4)

# Prometheus file_sd target for Grafana
cat > /opt/monitoring/config/prometheus/grafana.json <<EOF
[{"targets":["$LOCAL_IP:3000"],"labels":{"job":"grafana","service":"grafana"}}]
EOF

# Grafana provisioning: datasources
mkdir -p /opt/monitoring/config/grafana/provisioning/datasources

cat > /opt/monitoring/config/grafana/provisioning/datasources/datasources.yaml << 'EOF'
apiVersion: 1
datasources:
  - name: Prometheus
    uid: prom
    type: prometheus
    access: proxy
    url: http://localhost:9090
    isDefault: true
    editable: false
    jsonData:
      httpMethod: POST
      manageAlerts: true

  - name: Loki
    uid: loki
    type: loki
    access: proxy
    url: http://localhost:3100
    editable: false
    jsonData:
      maxLines: 1000

  - name: CloudWatch
    uid: cw
    type: cloudwatch
    access: proxy
    editable: false
    jsonData:
      authType: default
      defaultRegion: ${aws_region}
EOF

# Set permissions
chown -R 472:472 /var/lib/grafana
chown -R 65534:65534 /var/lib/prometheus  
chown -R 10001:10001 /var/lib/loki

# Install docker-compose
curl -L "https://github.com/docker/compose/releases/download/v2.21.0/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
chmod +x /usr/local/bin/docker-compose

# Create Prometheus config
cat > /opt/monitoring/config/prometheus/prometheus.yml << 'EOF'
global:
  scrape_interval: 15s
  external_labels:
    cluster: 'cs1-ma-nca'
    region: 'eu-central-1'

rule_files:
  - "alert_rules.yml"

scrape_configs:
  - job_name: 'prometheus'
    static_configs:
      - targets: ['localhost:9090']

  - job_name: 'cloudwatch-rds'
    static_configs:
      - targets: ['cloudwatch-exporter:9106']
    scrape_interval: 60s

  - job_name: 'web-servers'
    file_sd_configs:
      - files: ['/etc/prometheus/web_servers.json']
        refresh_interval: 30s

  - job_name: 'nat-instance'
    static_configs:
      - targets: ['${nat_instance_ip}:9100']
        labels:
          service: 'nat-instance'

  - job_name: 'grafana'
    metrics_path: /metrics
    scheme: http
    file_sd_configs:
      - files: ['/etc/prometheus/grafana.json']
        refresh_interval: 30s
EOF

# Create basic alert rules
cat > /opt/monitoring/config/prometheus/alert_rules.yml << 'EOF'
groups:
  - name: infrastructure
    rules:
      - alert: HighCPUUsage
        expr: 100 - (avg(rate(node_cpu_seconds_total{mode="idle"}[5m])) * 100) > 80
        for: 5m
        labels:
          severity: warning
        annotations:
          summary: "High CPU usage on {{ $labels.instance }}"
      - alert: WebServerDown
        expr: up{job="web-servers"} == 0
        for: 2m
        labels:
          severity: critical
        annotations:
          summary: "Web server {{ $labels.instance }} is down"
EOF

# Create web servers discovery file
cat > /opt/monitoring/config/prometheus/web_servers.json << 'EOF'
[{"targets": [],"labels": {"job": "web-servers","service": "apache"}}]
EOF

# Create CloudWatch config
cat > /opt/monitoring/config/prometheus/cloudwatch.yml << 'EOF'
region: eu-central-1
period_seconds: 300
set_timestamp: true
metrics:
  - aws_namespace: AWS/RDS
    aws_metric_name: CPUUtilization
    aws_dimensions: [DBInstanceIdentifier]
    aws_dimension_select:
      DBInstanceIdentifier: ["${db_identifier}"]
    aws_statistics: [Average]
  - aws_namespace: AWS/RDS
    aws_metric_name: DatabaseConnections
    aws_dimensions: [DBInstanceIdentifier]
    aws_dimension_select:
      DBInstanceIdentifier: ["${db_identifier}"]
    aws_statistics: [Average]
  - aws_namespace: AWS/ApplicationELB
    aws_metric_name: RequestCount
    aws_dimensions: [LoadBalancer]
    aws_statistics: [Sum]
EOF

# Create Loki config
cat > /opt/monitoring/config/loki/loki.yml << 'EOF'
auth_enabled: false

server:
  http_listen_port: 3100

ingester:
  lifecycler:
    address: 127.0.0.1
    ring:
      kvstore:
        store: inmemory
      replication_factor: 1
    final_sleep: 0s
  chunk_idle_period: 1h
  max_chunk_age: 1h
  chunk_target_size: 1048576
  chunk_retain_period: 30s
  wal:
    enabled: true
    dir: /loki/wal

schema_config:
  configs:
    - from: 2020-10-24
      store: boltdb-shipper
      object_store: filesystem
      schema: v11
      index:
        prefix: index_
        period: 24h

storage_config:
  boltdb_shipper:
    active_index_directory: /loki/boltdb-shipper-active
    cache_location: /loki/boltdb-shipper-cache
  filesystem:
    directory: /loki/chunks

compactor:
  working_directory: /loki/compactor
  compaction_interval: 10m

limits_config:
  reject_old_samples: true
  reject_old_samples_max_age: 168h
  allow_structured_metadata: false
EOF

# Create docker-compose file
cat > /opt/monitoring/docker-compose.yml << 'EOF'
version: '3.8'
services:
  prometheus:
    image: prom/prometheus:latest
    container_name: prometheus
    ports: ["9090:9090"]
    volumes:
      - /opt/monitoring/config/prometheus:/etc/prometheus
      - /var/lib/prometheus:/prometheus
    command:
      - '--config.file=/etc/prometheus/prometheus.yml'
      - '--storage.tsdb.path=/prometheus'
      - '--storage.tsdb.retention.time=30d'
      - '--web.enable-lifecycle'
    restart: unless-stopped
    user: "65534:65534"
  grafana:
    image: grafana/grafana:latest
    container_name: grafana
    network_mode: host
    volumes:
      - /var/lib/grafana:/var/lib/grafana
      - /opt/monitoring/config/grafana/provisioning:/etc/grafana/provisioning
    environment:
      - GF_SECURITY_ADMIN_PASSWORD=admin123
      - GF_SERVER_HTTP_ADDR=0.0.0.0
      - GF_METRICS_ENABLED=true          # <— expose /metrics
      - GF_METRICS_INTERVAL=10s          # optional, default is fine too
    restart: unless-stopped
    user: "472:472"
  loki:
    image: grafana/loki:latest
    container_name: loki
    ports: ["3100:3100"]
    volumes:
      - /opt/monitoring/config/loki:/etc/loki
      - /var/lib/loki:/loki
    command: --config.file=/etc/loki/loki.yml
    restart: unless-stopped
    user: "10001:10001"
  cloudwatch-exporter:
    image: prom/cloudwatch-exporter:latest
    container_name: cloudwatch-exporter
    ports: ["9106:9106"]
    volumes:
      - /opt/monitoring/config/prometheus/cloudwatch.yml:/config/config.yml
    command: /config/config.yml
    restart: unless-stopped
EOF

# Create discovery script
cat > /opt/monitoring/discover_web_servers.sh << 'EOF'
#!/bin/bash
asg_name="cs1-ma-nca-web-asg"
instances=$(aws autoscaling describe-auto-scaling-groups --auto-scaling-group-names "$asg_name" --region eu-central-1 --query 'AutoScalingGroups[0].Instances[?LifecycleState==`InService`].InstanceId' --output text 2>/dev/null)
targets=""
if [[ -n "$instances" && "$instances" != "None" ]]; then
    for instance_id in $instances; do
        private_ip=$(aws ec2 describe-instances --instance-ids "$instance_id" --region eu-central-1 --query 'Reservations[0].Instances[0].PrivateIpAddress' --output text 2>/dev/null)
        if [[ -n "$private_ip" && "$private_ip" != "None" ]]; then
            [[ -n "$targets" ]] && targets="$targets,"
            targets="$targets\"$private_ip:9100\""
        fi
    done
fi
echo '[{"targets":['$targets'],"labels":{"job":"web-servers","service":"apache"}}]' > /opt/monitoring/config/prometheus/web_servers.json
curl -X POST http://localhost:9090/-/reload >/dev/null 2>&1
EOF

chmod +x /opt/monitoring/discover_web_servers.sh

# Start monitoring stack
cd /opt/monitoring
sudo /usr/local/bin/docker-compose up -d

# Add discovery cron job
echo "*/2 * * * * root /opt/monitoring/discover_web_servers.sh" >> /etc/crontab

# Create status script
cat > /home/ec2-user/monitoring-status.sh << 'EOF'
#!/bin/bash
echo "=== Monitoring Status ==="
sudo /usr/local/bin/docker-compose -f /opt/monitoring/docker-compose.yml ps
echo "=== Service URLs (via VPN) ==="
LOCAL_IP=$(curl -s http://169.254.169.254/latest/meta-data/local-ipv4)
echo "Grafana: http://$LOCAL_IP:3000 (admin/admin123)"
echo "Prometheus: http://$LOCAL_IP:9090"
echo "Loki: http://$LOCAL_IP:3100"
EOF

chmod +x /home/ec2-user/monitoring-status.sh
chown ec2-user:ec2-user /home/ec2-user/monitoring-status.sh

LOCAL_IP=$(curl -s http://169.254.169.254/latest/meta-data/local-ipv4)
log "Monitoring setup complete. Access via VPN:"
log "- Grafana: http://$LOCAL_IP:3000 (admin/admin123)"
log "- Prometheus: http://$LOCAL_IP:9090"