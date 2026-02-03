import json
import boto3
import os
from datetime import datetime

sns = boto3.client('sns')
ses = boto3.client('ses')

def handler(event, context):
    """
    Sends email notifications for high-priority security events
    Handles both SQS and direct EventBridge invocations
    """
    sns_topic = os.environ['SNS_TOPIC_ARN']
    sender_email = os.environ['SENDER_EMAIL']
    
    # Detect event source
    if 'Records' in event:
        # SQS event format
        events_to_process = []
        for record in event['Records']:
            message = json.loads(record['body'])
            events_to_process.append(message.get('detail', {}))
    else:
        # Direct EventBridge invocation
        events_to_process = [event.get('detail', {})]
    
    # Process each event
    for detail in events_to_process:
        severity = detail.get('severity', 'unknown')
        event_type = detail.get('event_type', 'unknown')
        source_ip = detail.get('source_ip', 'unknown')
        timestamp = detail.get('timestamp', datetime.now().isoformat())
        
        # Create email subject and body
        subject = f"[SOAR ALERT] {severity.upper()} - {event_type}"
        body = f"""
Security Event Detected
=======================

Severity: {severity}
Event Type: {event_type}
Source IP: {source_ip}
Timestamp: {timestamp}

Details:
{json.dumps(detail, indent=2)}

This is an automated alert from the SOAR system.
"""
        
        # Send via SNS (for multiple subscribers)
        try:
            sns.publish(
                TopicArn=sns_topic,
                Subject=subject,
                Message=body
            )
            print(f"Sent SNS notification for event: {event_type}")
        except Exception as e:
            print(f"Error sending SNS: {e}")
            
        # Also send direct email via SES (for formatting)
        try:
            ses.send_email(
                Source=sender_email,
                Destination={
                    'ToAddresses': [sender_email]
                },
                Message={
                    'Subject': {'Data': subject},
                    'Body': {'Text': {'Data': body}}
                }
            )
            print(f"Sent SES email for event: {event_type}")
        except Exception as e:
            print(f"Error sending SES email: {e}")
    
    return {
        'statusCode': 200,
        'body': json.dumps(f'Processed {len(events_to_process)} events')
    }
