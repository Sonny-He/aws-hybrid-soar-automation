#!/bin/bash

# Logging function
log() {
    echo "$(date): $1" >> /var/log/openvpn-setup.log
    echo "$1"
}

# Check if already configured
if [ -d /etc/openvpn/pki ] && [ -f /etc/openvpn/server.conf ]; then
    log "OpenVPN already configured - skipping setup"
    systemctl enable --now openvpn@server
    exit 0
fi

log "Starting OpenVPN server setup..."

# Update system
yum update -y

# Install EPEL repository and OpenVPN (REMOVED httpd)
amazon-linux-extras install -y epel
yum install -y openvpn easy-rsa

# Enable IP forwarding
echo 'net.ipv4.ip_forward = 1' >> /etc/sysctl.conf
sysctl -p

log "OpenVPN and Easy-RSA installed"

# Setup Easy-RSA for certificate management
cd /etc/openvpn
cp -r /usr/share/easy-rsa/3/* .

# Initialize PKI
./easyrsa init-pki
echo "cs1-ma-nca-ca" | ./easyrsa build-ca nopass
./easyrsa build-server-full server nopass
./easyrsa build-client-full client nopass
./easyrsa gen-dh

# Generate additional security files
openvpn --genkey --secret ta.key

log "Certificates and keys generated"

# Create OpenVPN server configuration
cat > /etc/openvpn/server.conf << EOF
# OpenVPN Server Configuration
port 1194
proto udp
dev tun

# Certificates and keys
ca pki/ca.crt
cert pki/issued/server.crt
key pki/private/server.key
dh pki/dh.pem
tls-auth ta.key 0

# Network configuration
server 10.8.0.0 255.255.255.0
ifconfig-pool-persist /etc/openvpn/ipp.txt

# Route ONLY VPC networks to VPN clients (NOT all traffic)
push "route 10.0.0.0 255.255.0.0"

# DNS settings (use AWS DNS for VPC resources)
push "dhcp-option DNS 10.0.0.2"

# Security settings
cipher AES-256-GCM
auth SHA256
keepalive 10 120
tls-version-min 1.2
tls-cipher TLS-ECDHE-RSA-WITH-AES-256-GCM-SHA384

# User/group (security)
user nobody
group nobody
persist-key
persist-tun

# Logging
status /var/log/openvpn-status.log
log-append /var/log/openvpn.log
verb 3
mute 20

# Allow client-to-client communication
client-to-client

# Compression (optional)
compress lz4-v2
push "compress lz4-v2"
EOF

log "Server configuration created"

# Configure iptables for NAT and forwarding
# IMPORTANT: do NOT NAT traffic from VPN clients (10.8.0.0/24) to the VPC (10.0.0.0/16).
# This preserves the original client IP so your SOAR SG rule (allowing 10.8.0.0/24) works.
iptables -t nat -I POSTROUTING 1 -s ${vpn_client_cidr} -d ${vpc_cidr} -j ACCEPT

# Keep NAT for Internet-bound traffic from VPN clients
iptables -t nat -A POSTROUTING -s ${vpn_client_cidr} -o eth0 -j MASQUERADE

# Forwarding rules for OpenVPN
iptables -A FORWARD -i tun0 -o eth0 -j ACCEPT
iptables -A FORWARD -i eth0 -o tun0 -m state --state RELATED,ESTABLISHED -j ACCEPT

# Allow OpenVPN UDP port
iptables -A INPUT -p udp --dport 1194 -j ACCEPT

# Save iptables rules and ensure they restore on boot
iptables-save > /etc/iptables.rules
cat >/etc/systemd/system/restore-iptables.service <<'EOF'
[Unit]
Description=Restore iptables rules
DefaultDependencies=no
Before=network-pre.target
Wants=network-pre.target

[Service]
Type=oneshot
ExecStart=/sbin/iptables-restore /etc/iptables.rules
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
EOF
systemctl enable restore-iptables

# Create script to restore iptables on boot
cat > /etc/rc.local << 'EOF'
#!/bin/bash
iptables-restore < /etc/iptables.rules
exit 0
EOF
chmod +x /etc/rc.local

log "Firewall configured"

# Start and enable OpenVPN
systemctl start openvpn@server
systemctl enable openvpn@server

log "OpenVPN server started"

# Create client configuration file with WORKING inline certificates (using the fix from previous chat)
mkdir -p /etc/openvpn/client-configs

# Use the WORKING method from manual recreation (with sudo cat)
cat > /etc/openvpn/client-configs/client.ovpn << EOF
client
dev tun
proto udp
remote $(curl -s http://169.254.169.254/latest/meta-data/public-ipv4) 1194
resolv-retry infinite
nobind
persist-key
persist-tun
route 10.0.0.0 255.255.0.0  
cipher AES-256-GCM
auth SHA256
key-direction 1
verb 3
compress lz4-v2

<ca>
$(sudo cat /etc/openvpn/pki/ca.crt)
</ca>

<cert>
$(sudo cat /etc/openvpn/pki/issued/client.crt)
</cert>

<key>
$(sudo cat /etc/openvpn/pki/private/client.key)
</key>

<tls-auth>
$(sudo cat /etc/openvpn/ta.key)
</tls-auth>
EOF

log "Client configuration created with inline certificates (using sudo cat fix)"

# SECURE: Make client config accessible to ec2-user via SCP only
chown ec2-user:ec2-user /etc/openvpn/client-configs/client.ovpn
chmod 600 /etc/openvpn/client-configs/client.ovpn

# Create a copy in ec2-user home for easy SCP access
cp /etc/openvpn/client-configs/client.ovpn /home/ec2-user/client.ovpn
chown ec2-user:ec2-user /home/ec2-user/client.ovpn
chmod 600 /home/ec2-user/client.ovpn

log "Client configuration created securely"

# Create status check script with SCP instructions
cat > /home/ec2-user/openvpn-status.sh << 'EOF'
#!/bin/bash
echo "=== OpenVPN Status ==="
echo "Service Status: $(systemctl is-active openvpn@server)"
echo "Connected Clients:"
if [ -f /var/log/openvpn-status.log ]; then
    grep "CLIENT_LIST" /var/log/openvpn-status.log 2>/dev/null || echo "No clients connected"
else
    echo "Status log not available yet"
fi
echo ""
echo "=== Server Info ==="
echo "Public IP: $(curl -s http://169.254.169.254/latest/meta-data/public-ipv4)"
echo "VPN Network: ${vpn_client_cidr}"
echo "VPC Network: ${vpc_cidr}"
echo ""
echo "=== Secure Download ==="
echo "SCP command: scp -i ~/.ssh/aws-cs1-key ec2-user@$(curl -s http://169.254.169.254/latest/meta-data/public-ipv4):client.ovpn C:/Users/sonny/cs1-ma-nca-infrastructure/"
echo "Config location: /home/ec2-user/client.ovpn"
EOF

chmod +x /home/ec2-user/openvpn-status.sh

# Wait for OpenVPN to fully start
sleep 10

# Check if OpenVPN is running
if systemctl is-active --quiet openvpn@server; then
    log "SUCCESS: OpenVPN server is running"
else
    log "ERROR: OpenVPN server failed to start"
    systemctl status openvpn@server >> /var/log/openvpn-setup.log
fi

log "OpenVPN server setup completed successfully"
log "Public IP: $(curl -s http://169.254.169.254/latest/meta-data/public-ipv4)"
log "Client config: Use SCP to download /home/ec2-user/client.ovpn"
log "SCP command: scp -i ~/.ssh/aws-cs1-key ec2-user@$(curl -s http://169.254.169.254/latest/meta-data/public-ipv4):client.ovpn C:/Users/sonny/cs1-ma-nca-infrastructure/"
log "VPN provides access to VPC: ${vpc_cidr}"
log "Check status with: ./openvpn-status.sh"