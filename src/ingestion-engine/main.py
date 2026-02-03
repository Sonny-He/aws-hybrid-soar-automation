import socket
import json
import boto3
import os
import re
from datetime import datetime
from http.server import HTTPServer, BaseHTTPRequestHandler
import threading

# AWS clients
events = boto3.client('events')

# Configuration - CHANGED TO NON-PRIVILEGED PORT
SYSLOG_PORT = 5140  # Changed from 514 to avoid privileged port issues
HEALTH_PORT = 8080
EVENT_BUS_NAME = os.environ.get('EVENTBRIDGE_BUS_NAME', 'cs1-ma-nca-soar-events')

class HealthCheckHandler(BaseHTTPRequestHandler):
    """Simple HTTP health check endpoint"""
    def do_GET(self):
        if self.path == '/health':
            self.send_response(200)
            self.send_header('Content-type', 'application/json')
            self.end_headers()
            self.wfile.write(json.dumps({'status': 'healthy'}).encode())
        else:
            self.send_response(404)
            self.end_headers()
    
    def log_message(self, format, *args):
        pass  # Suppress logs

def parse_syslog(message: str, peer_ip: str | None = None):
    """
    Parse RFC3164-ish syslog like:
      <PRI>MMM dd HH:MM:SS HOST APP[:PID]: MSG
    Derive severity, event_type, and source_ip.
    """
    # --- PRI -> severity code (0..7), facility ignored here
    pri_match = re.match(r'^<(\d+)>', message)
    pri = int(pri_match.group(1)) if pri_match else 13  # default "notice"
    sev_code = pri & 0x7  # same as pri % 8

    # severity mapping (collapse to your buckets)
    sev_names = ['critical', 'critical', 'high', 'high', 'medium', 'low', 'low', 'low']
    severity = sev_names[sev_code]

    # --- header parse (host, app, msg)
    hdr = re.match(
        r'^<\d+>(?P<ts>[A-Z][a-z]{2}\s+\d{1,2}\s+\d{2}:\d{2}:\d{2})\s+(?P<host>\S+)\s+(?P<app>\S+?)(?:\[\d+\])?:\s*(?P<msg>.*)$',
        message
    )
    host = hdr.group('host') if hdr else None
    app  = hdr.group('app')  if hdr else None
    msg  = hdr.group('msg')  if hdr else message

    # --- event_type detection (simple rules, extend as you like)
    lower = msg.lower()
    if 'failed login' in lower or 'login failed' in lower or 'authentication failed' in lower:
        event_type = 'failed_login'
    elif 'brute' in lower and 'force' in lower:
        event_type = 'bruteforce'
    elif 'unauthorized' in lower or 'denied' in lower:
        event_type = 'unauthorized_access'
    elif 'malware' in lower or 'virus' in lower:
        event_type = 'malware_detected'
    else:
        event_type = 'general_security_event'

    # Upgrade severity for critical authentication events
    # SSH failures should always trigger email alerts
    if ('failed' in lower and 'password' in lower) or \
       ('failed' in lower and 'login' in lower) or \
       ('authentication failure' in lower):
        if severity in ['low', 'medium']:
            severity = 'high'  # Upgrade to trigger email + IP block

    # Extract IP addresses
    # --- source_ip: first IPv4 in message; if none, fall back to peer_ip
    ip_pattern = r'\b(?:\d{1,3}\.){3}\d{1,3}\b'
    m = re.search(ip_pattern, msg)
    source_ip = m.group(0) if m else (peer_ip or 'unknown')

    return {
        'schema_version': '1.0',
        'severity': severity,
        'event_type': event_type,
        'source_ip': source_ip,
        'source_host': peer_ip or host or 'unknown',
        'app': app or 'unknown',
        'raw_message': message,
        'timestamp': datetime.utcnow().isoformat() + 'Z'
    }


def send_to_eventbridge(event_detail):
    """Send parsed event to EventBridge"""
    try:
        response = events.put_events(
            Entries=[{
                'Source': 'soar.collector',
                'DetailType': 'SecurityEvent',
                'Detail': json.dumps(event_detail),
                'EventBusName': EVENT_BUS_NAME
            }]
        )
        
        if response['FailedEntryCount'] > 0:
            print(f"Failed to send event: {response['Entries']}")
        else:
            print(f"Sent event to EventBridge: {event_detail['event_type']} ({event_detail['severity']})")
            
    except Exception as e:
        print(f"Error sending to EventBridge: {e}")

def start_syslog_listener():
    """Start UDP syslog listener"""
    sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    sock.bind(('0.0.0.0', SYSLOG_PORT))
    
    print(f"Syslog listener started on UDP port {SYSLOG_PORT}")
    
    while True:
        try:
            data, addr = sock.recvfrom(4096)
            message = data.decode('utf-8', errors='ignore')
            
            print(f"Received syslog from {addr[0]}: {message[:100]}...")
            
            event_detail = parse_syslog(message, peer_ip=addr[0])
            
            # Send to EventBridge for further processing
            send_to_eventbridge(event_detail)
            
        except Exception as e:
            print(f"Error processing syslog: {e}")

def start_health_server():
    """Start HTTP health check server"""
    server = HTTPServer(('0.0.0.0', HEALTH_PORT), HealthCheckHandler)
    print(f"Health check server started on port {HEALTH_PORT}")
    server.serve_forever()

if __name__ == '__main__':
    print("=" * 60)
    print("SOAR Event Collector & Rule Engine")
    print(f"EventBridge Bus: {EVENT_BUS_NAME}")
    print(f"Syslog Port: {SYSLOG_PORT} (non-privileged)")
    print("=" * 60)
    
    # Start health check server in separate thread
    health_thread = threading.Thread(target=start_health_server, daemon=True)
    health_thread.start()
    
    # Start syslog listener (blocking)
    start_syslog_listener()