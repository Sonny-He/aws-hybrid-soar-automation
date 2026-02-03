#!/bin/bash

# Logging function
log() {
    echo "$(date): $1" >> /var/log/user-data.log
    echo "$1"
}

log "Starting web server setup..."

# Update system
yum update -y

# Install Apache2, PHP, and MySQL client
yum install -y httpd php php-mysqlnd mysql

# Start and enable Apache
systemctl start httpd
systemctl enable httpd

log "Apache installed and started"

# CREATE IMMEDIATE HEALTH CHECK ENDPOINT (ALB can pass immediately)
echo "OK" > /var/www/html/health
chown apache:apache /var/www/html/health
chmod 644 /var/www/html/health

log "Basic health check endpoint created - ALB should pass now"

# Get instance metadata for static HTML
INSTANCE_ID=$(curl -s http://169.254.169.254/latest/meta-data/instance-id)
CURRENT_TIME=$(date)

# Create simple fallback HTML page (works without database)
cat > /var/www/html/index.html << EOF
<!DOCTYPE html>
<html>
<head>
    <meta charset="UTF-8">
    <title>CS1-MA-NCA Web Server</title>
    <style>
        body { font-family: Arial, sans-serif; margin: 40px; background: #f5f5f5; }
        .container { background: white; padding: 30px; border-radius: 10px; }
        .loading { color: orange; }
    </style>
</head>
<body>
    <div class="container">
        <h1>CS1-MA-NCA Web Server</h1>
        <p class="loading">Server is initializing... Database connection in progress.</p>
        <p><a href="index.php">Try PHP application</a> (may take a few minutes to load)</p>
        <p><strong>Instance ID:</strong> $INSTANCE_ID</p>
        <p><strong>Server Time:</strong> $CURRENT_TIME</p>
    </div>
</body>
</html>
EOF

# Set basic permissions
chown -R apache:apache /var/www/html
chmod -R 755 /var/www/html

# Restart Apache to ensure everything is working
systemctl restart httpd

log "Basic web server is ready - continuing with Node Exporter installation"

# Install Node Exporter for Prometheus monitoring (MUST complete BEFORE background tasks)
log "Installing Node Exporter for monitoring..."

cd /tmp
wget -q https://github.com/prometheus/node_exporter/releases/download/v1.6.1/node_exporter-1.6.1.linux-amd64.tar.gz
tar xzf node_exporter-1.6.1.linux-amd64.tar.gz
mv node_exporter-1.6.1.linux-amd64/node_exporter /usr/local/bin/
rm -rf node_exporter-1.6.1.linux-amd64*

useradd --no-create-home --shell /bin/false node_exporter
chown node_exporter:node_exporter /usr/local/bin/node_exporter

cat > /etc/systemd/system/node_exporter.service << 'NODEEOF'
[Unit]
Description=Node Exporter
After=network.target

[Service]
User=node_exporter
Group=node_exporter
Type=simple
ExecStart=/usr/local/bin/node_exporter

[Install]
WantedBy=multi-user.target
NODEEOF

systemctl daemon-reload
systemctl start node_exporter
systemctl enable node_exporter

if systemctl is-active --quiet node_exporter; then
    log "Node Exporter started successfully on port 9100"
else
    log "ERROR: Node Exporter failed to start"
    systemctl status node_exporter >> /var/log/user-data.log 2>&1
fi

log "Node Exporter installation completed"

# Database setup in background (doesn't block health checks or Node Exporter)
{
    log "Starting database connection setup..."
    
    # Get database endpoint and strip port for MySQL client
    DB_ENDPOINT="${db_endpoint}"
    DB_HOST="$${DB_ENDPOINT%:*}"
    
    # DEBUG: Log the actual values being used
    log "DEBUG: Raw DB_ENDPOINT from Terraform: '$DB_ENDPOINT'"
    log "DEBUG: Processed DB_HOST (without port): '$DB_HOST'"
    
    # Test connection immediately (don't wait 10 minutes first)
    log "Testing IMMEDIATE database connection to: $DB_HOST"
    if mysql -h "$DB_HOST" -u admin -pChangeMe123! -e "SELECT 1" 2>&1 | tee -a /var/log/user-data.log; then
        log "SUCCESS: Database is already ready!"
        DB_READY=true
    else
        log "Database not ready yet, starting wait cycle..."
        log "Will wait 10 minutes then start testing every 30 seconds..."
        
        # Wait for RDS to be ready
        log "Waiting initial 10 minutes for RDS..."
        sleep 600
        
        # Test database connection with extended retry
        log "Starting connection retry loop..."
        DB_READY=false
        for i in {1..60}; do
            log "=== Connection attempt $i/60 to: $DB_HOST ==="
            
            # Test with full output visible
            if mysql -h "$DB_HOST" -u admin -pChangeMe123! -e "SELECT 1" 2>&1 | tee -a /var/log/user-data.log; then
                log "SUCCESS: Database connection successful on attempt $i!"
                DB_READY=true
                break
            else
                log "FAILED: Attempt $i failed, waiting 30 seconds..."
                
                # Every 10 attempts, show network connectivity
                if [ $((i % 10)) -eq 0 ]; then
                    log "=== Network diagnostics (attempt $i) ==="
                    nslookup "$DB_HOST" 2>&1 | tee -a /var/log/user-data.log
                    ping -c 2 "$DB_HOST" 2>&1 | tee -a /var/log/user-data.log || log "Ping failed (expected - RDS doesn't respond to ping)"
                fi
                
                sleep 30
            fi
        done
    fi
    
    if [ "$DB_READY" = false ]; then
        log "ERROR: Database connection failed after all attempts"
        log "=== Final diagnostics ==="
        log "DB_ENDPOINT: '$DB_ENDPOINT'"
        log "DB_HOST: '$DB_HOST'"
        log "Final connection test with full verbose output:"
        mysql -h "$DB_HOST" -u admin -pChangeMe123! -e "SELECT 1" -v 2>&1 | tee -a /var/log/user-data.log
        
        log "Network resolution test:"
        nslookup "$DB_HOST" 2>&1 | tee -a /var/log/user-data.log
        
        # Create error page with diagnostics
        cat > /var/www/html/db_error.html << ERROREOF
<h1>Database Connection Failed</h1>
<p><strong>Database Host:</strong> $DB_HOST</p>
<p><strong>Original Endpoint:</strong> $DB_ENDPOINT</p>
<p>Check the logs: <code>sudo tail -f /var/log/user-data.log</code></p>
<p>Database may still be initializing. RDS can take 15-20 minutes to be ready.</p>
ERROREOF
    else
        # Database is ready - create PHP application with enhanced visual load balancing
        log "Creating PHP application with enhanced load balancer visualization..."
        
        cat > /var/www/html/index.php << 'PHPEOF'
<?php
ini_set('default_charset', 'UTF-8');

$servername = "DB_HOST_PLACEHOLDER";
$username = "admin";
$password = "ChangeMe123!";
$dbname = "webapp";

$instance_id = file_get_contents("http://169.254.169.254/latest/meta-data/instance-id");
$az = file_get_contents("http://169.254.169.254/latest/meta-data/placement/availability-zone");
$private_ip = file_get_contents("http://169.254.169.254/latest/meta-data/local-ipv4");

// Generate consistent color based on instance ID for visual differentiation
$color_hash = substr(md5($instance_id), 0, 6);

$db_status = "Disconnected";
$visit_count = 0;

try {
    $conn = new mysqli($servername, $username, $password, $dbname);
    $conn->set_charset("utf8mb4");
    
    if ($conn->connect_error) {
        throw new Exception("Connection failed: " . $conn->connect_error);
    }
    $db_status = "Connected";
    
    $sql = "CREATE TABLE IF NOT EXISTS visits (
        id INT AUTO_INCREMENT PRIMARY KEY,
        instance_id VARCHAR(255),
        visit_time TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
        user_ip VARCHAR(45),
        availability_zone VARCHAR(50)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4";
    $conn->query($sql);
    
    $user_ip = isset($_SERVER['REMOTE_ADDR']) ? $_SERVER['REMOTE_ADDR'] : 'unknown';
    $stmt = $conn->prepare("INSERT INTO visits (instance_id, user_ip, availability_zone) VALUES (?, ?, ?)");
    $stmt->bind_param("sss", $instance_id, $user_ip, $az);
    $stmt->execute();
    
    $result = $conn->query("SELECT COUNT(*) as count FROM visits");
    if ($result) {
        $row = $result->fetch_assoc();
        $visit_count = $row['count'];
    }
    
    $conn->close();
} catch (Exception $e) {
    $db_status = "Error: " . $e->getMessage();
}
?>
<!DOCTYPE html>
<html>
<head>
    <meta charset="UTF-8">
    <title>CS1-MA-NCA Multi-AZ Architecture</title>
    <style>
        body { 
            font-family: Arial, sans-serif; 
            margin: 40px; 
            background: #f5f5f5; 
        }
        .container { 
            background: white; 
            padding: 30px; 
            border-radius: 10px; 
            box-shadow: 0 2px 10px rgba(0,0,0,0.1);
        }
        .status { 
            color: <?php echo ($db_status === "Connected") ? "green" : "red"; ?>; 
            font-weight: bold; 
        }
        .instance-badge {
            display: inline-block;
            padding: 10px 20px;
            background: #<?php echo $color_hash; ?>;
            color: white;
            border-radius: 5px;
            font-size: 1.2em;
            font-weight: bold;
            margin: 10px 0;
            box-shadow: 0 2px 5px rgba(0,0,0,0.2);
        }
        .load-balancer-notice {
            background: #fff3cd;
            border-left: 4px solid #ffc107;
            padding: 15px;
            margin: 20px 0;
            border-radius: 5px;
        }
        .info { 
            margin: 10px 0; 
            padding: 10px; 
            background: #e9f4ff; 
            border-radius: 5px; 
        }
        .debug { 
            font-size: 0.9em; 
            color: #666; 
            background: #f0f0f0; 
            padding: 10px; 
            border-radius: 5px; 
        }
    </style>
</head>
<body>
    <div class="container">
        <h1>🚀 CS1-MA-NCA Multi-AZ Infrastructure</h1>
        
        <div class="load-balancer-notice">
            <strong>⚖️ Load Balancer Active!</strong> Refresh this page to see the instance change.
            <br>Each instance has a unique color badge below.
        </div>
        
        <div style="text-align: center;">
            <div class="instance-badge">
                Instance: <?php echo htmlspecialchars($instance_id); ?>
            </div>
            <p><strong>Availability Zone:</strong> <?php echo htmlspecialchars($az); ?></p>
            <p><strong>Private IP:</strong> <?php echo htmlspecialchars($private_ip); ?></p>
        </div>
        
        <div class="status">Database Status: <?php echo htmlspecialchars($db_status); ?></div>
        
        <div class="info">
            <h3>📊 Statistics</h3>
            <p><strong>Total Visits Across All Instances:</strong> <?php echo number_format($visit_count); ?></p>
            <p><strong>Current Time:</strong> <?php echo date('Y-m-d H:i:s'); ?></p>
        </div>
        
        <div class="info">
            <h3>🏗️ Architecture Features</h3>
            <ul>
                <li>✅ Multi-AZ deployment (eu-central-1a & 1b)</li>
                <li>✅ Application Load Balancer (distributing traffic)</li>
                <li>✅ Auto-scaling (2-10 instances)</li>
                <li>✅ RDS MySQL database (shared across instances)</li>
                <li>✅ Cost-optimized with single NAT instance</li>
                <li>✅ Prometheus monitoring with Node Exporter</li>
            </ul>
        </div>
        
        <div class="debug">
            <h4>🔧 Debug Info</h4>
            <p><strong>DB Server:</strong> <?php echo htmlspecialchars($servername); ?></p>
            <p><strong>DB Name:</strong> <?php echo htmlspecialchars($dbname); ?></p>
            <p><strong>PHP Version:</strong> <?php echo phpversion(); ?></p>
            <p><strong>Node Exporter:</strong> http://<?php echo $_SERVER['SERVER_ADDR']; ?>:9100/metrics</p>
        </div>
        
        <p style="text-align: center; margin-top: 20px;">
            <em>🔄 Keep refreshing to see load balancing in action!</em>
        </p>
    </div>
</body>
</html>
PHPEOF

        # Replace placeholder in PHP file
        sed -i "s/DB_HOST_PLACEHOLDER/$DB_HOST/g" /var/www/html/index.php

        # Health check with database info
        cat > /var/www/html/health.php << 'HEALTHEOF'
<?php
header('Content-Type: application/json; charset=UTF-8');
$health = array(
    'status' => 'healthy',
    'timestamp' => date('Y-m-d H:i:s'),
    'instance_id' => file_get_contents("http://169.254.169.254/latest/meta-data/instance-id"),
    'service' => 'web-server',
    'database_host' => 'DB_HOST_PLACEHOLDER',
    'node_exporter' => 'http://' . $_SERVER['SERVER_ADDR'] . ':9100/metrics'
);

try {
    $conn = new mysqli("DB_HOST_PLACEHOLDER", "admin", "ChangeMe123!", "webapp");
    $conn->set_charset("utf8mb4");
    
    if ($conn->connect_error) {
        $health['status'] = 'degraded';
        $health['db_status'] = 'disconnected';
        $health['db_error'] = $conn->connect_error;
    } else {
        $health['db_status'] = 'connected';
        
        $result = $conn->query("SELECT COUNT(*) as count FROM visits");
        if ($result) {
            $row = $result->fetch_assoc();
            $health['total_visits'] = (int)$row['count'];
        }
    }
    $conn->close();
} catch (Exception $e) {
    $health['status'] = 'degraded';
    $health['db_status'] = 'error';
    $health['db_error'] = $e->getMessage();
}

echo json_encode($health, JSON_PRETTY_PRINT);
?>
HEALTHEOF

        # Replace placeholder in health.php file
        sed -i "s/DB_HOST_PLACEHOLDER/$DB_HOST/g" /var/www/html/health.php

        # Set permissions
        chown -R apache:apache /var/www/html
        chmod -R 755 /var/www/html
        
        log "PHP application created successfully with enhanced load balancer visualization"
    fi
    
    log "Database setup completed - check /var/www/html/ for results"
    
} &  # Run database setup in background

# Verify Apache is running
if systemctl is-active --quiet httpd; then
    log "Apache is running successfully"
else
    log "ERROR: Apache failed to start"
    systemctl status httpd >> /var/log/user-data.log
fi

log "Web server setup completed successfully"
log "Database endpoint was: ${db_endpoint}"
log "Health check endpoint available immediately at /health"
log "Advanced health check with DB info at: /health.php"
log "Node Exporter metrics available at: http://$(curl -s http://169.254.169.254/latest/meta-data/local-ipv4):9100/metrics"
log "Check logs with: sudo tail -f /var/log/user-data.log"