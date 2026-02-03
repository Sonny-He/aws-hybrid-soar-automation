import json
import boto3
import os

ec2 = boto3.client('ec2')

def handler(event, context):
    """
    Blocks malicious IPs by adding them to Network ACL deny rules
    Handles both SQS and direct EventBridge invocations
    """
    vpc_id = os.environ['VPC_ID']
    
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
        source_ip = detail.get('source_ip')
        severity = detail.get('severity', 'unknown')
        
        # Only block for critical/high severity
        if severity not in ['critical', 'high']:
            print(f"Skipping IP block for {severity} severity event")
            continue
            
        if not source_ip:
            print("No source IP in event, skipping")
            continue
        
        # Block the IP
        try:
            # Get VPC's Network ACL
            response = ec2.describe_network_acls(
                Filters=[
                    {'Name': 'vpc-id', 'Values': [vpc_id]},
                    {'Name': 'default', 'Values': ['true']}
                ]
            )
            
            if not response['NetworkAcls']:
                print(f"No default Network ACL found for VPC {vpc_id}")
                continue
                
            nacl_id = response['NetworkAcls'][0]['NetworkAclId']
            
            # Find next available rule number (1-32766)
            existing_rules = response['NetworkAcls'][0]['Entries']
            rule_numbers = [rule['RuleNumber'] for rule in existing_rules]
            next_rule_number = 100  # Start at 100
            while next_rule_number in rule_numbers:
                next_rule_number += 1
            
            # Create deny rule for this IP
            ec2.create_network_acl_entry(
                NetworkAclId=nacl_id,
                RuleNumber=next_rule_number,
                Protocol='-1',  # All protocols
                RuleAction='deny',
                Egress=False,  # Inbound traffic
                CidrBlock=f"{source_ip}/32"
            )
            
            print(f"Blocked IP {source_ip} with rule {next_rule_number} in NACL {nacl_id}")
            
        except Exception as e:
            print(f"Error blocking IP {source_ip}: {e}")
            # Don't raise - we don't want to stop processing other events
    
    return {
        'statusCode': 200,
        'body': json.dumps(f'Processed {len(events_to_process)} IP block requests')
    }
