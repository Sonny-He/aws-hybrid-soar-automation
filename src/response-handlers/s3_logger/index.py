import json
import boto3
import os
from datetime import datetime

s3 = boto3.client('s3')

def handler(event, context):
    """
    Logs all security events to S3 for audit and analysis
    Handles both SQS and direct EventBridge invocations
    """
    bucket = os.environ['S3_BUCKET']
    
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
        # Generate S3 key with date partitioning
        now = datetime.now()
        severity = detail.get('severity', 'unknown')
        event_type = detail.get('event_type', 'unknown')
        
        key = f"events/{now.year}/{now.month:02d}/{now.day:02d}/{severity}/{event_type}_{now.timestamp()}.json"
        
        # Write to S3
        try:
            s3.put_object(
                Bucket=bucket,
                Key=key,
                Body=json.dumps(detail, indent=2),
                ContentType='application/json',
                ServerSideEncryption='AES256'
            )
            print(f"Logged event to S3: s3://{bucket}/{key}")
        except Exception as e:
            print(f"Error writing to S3: {e}")
            raise
    
    return {
        'statusCode': 200,
        'body': json.dumps(f'Logged {len(events_to_process)} events to S3')
    }
