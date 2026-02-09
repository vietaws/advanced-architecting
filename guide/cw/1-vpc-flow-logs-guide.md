Here's how to enable VPC Flow Logs and analyze the traffic:

## Step 1: Enable VPC Flow Logs

### Via AWS Console:
1. Go to VPC Console → Your VPC
2. Flow logs tab → Create flow log
3. Configure:
   - **Filter**: All (or Accepted/Rejected)
   - **Destination**: CloudWatch Logs
   - **Log group**: Create new (e.g., /aws/vpc/flowlogs)
   - **IAM role**: Create new or use existing

### Via AWS CLI:

bash
# Create CloudWatch log group
aws logs create-log-group \
  --log-group-name /aws/vpc/flowlogs \
  --region us-east-1

# Create IAM role for Flow Logs (save as trust-policy.json)
cat > trust-policy.json <<EOF
{
  "Version": "2012-10-17",
  "Statement": [{
    "Effect": "Allow",
    "Principal": {"Service": "vpc-flow-logs.amazonaws.com"},
    "Action": "sts:AssumeRole"
  }]
}
EOF

aws iam create-role \
  --role-name VPCFlowLogsRole \
  --assume-role-policy-document file://trust-policy.json

# Attach policy
aws iam put-role-policy \
  --role-name VPCFlowLogsRole \
  --policy-name VPCFlowLogsPolicy \
  --policy-document '{
    "Version": "2012-10-17",
    "Statement": [{
      "Effect": "Allow",
      "Action": [
        "logs:CreateLogGroup",
        "logs:CreateLogStream",
        "logs:PutLogEvents",
        "logs:DescribeLogGroups",
        "logs:DescribeLogStreams"
      ],
      "Resource": "*"
    }]
  }'

# Enable VPC Flow Logs
aws ec2 create-flow-logs \
  --resource-type VPC \
  --resource-ids vpc-xxxxx \
  --traffic-type ALL \
  --log-destination-type cloud-watch-logs \
  --log-group-name /aws/vpc/flowlogs \
  --deliver-logs-permission-arn arn:aws:iam::123456789012:role/VPCFlowLogsRole \
  --region us-east-1


## Step 2: Understanding VPC Flow Log Format

Default format (space-separated):
version account-id interface-id srcaddr dstaddr srcport dstport protocol packets bytes start end action log-status


Example log entry:
2 123456789012 eni-abc123 10.0.1.5 10.0.2.10 443 49152 6 20 4000 1612345678 1612345738 ACCEPT OK


Key fields:
- srcaddr/dstaddr: Source/destination IP
- srcport/dstport: Source/destination port
- protocol: 6=TCP, 17=UDP, 1=ICMP
- action: ACCEPT or REJECT
- bytes/packets: Traffic volume

## Step 3: View Logs

### Quick view via CLI:
bash
# List log streams
aws logs describe-log-streams \
  --log-group-name /aws/vpc/flowlogs \
  --order-by LastEventTime \
  --descending \
  --max-items 5 \
  --region us-east-1

# Get recent logs
aws logs tail /aws/vpc/flowlogs --follow --region us-east-1


## CloudWatch Logs Insights Queries

### 1. Top Talkers (Most Active IPs)
sql
fields @timestamp, srcaddr, dstaddr, bytes
| stats sum(bytes) as totalBytes by srcaddr
| sort totalBytes desc
| limit 20


### 2. Traffic to DynamoDB (via Gateway Endpoint)
sql
fields @timestamp, srcaddr, dstaddr, srcport, dstport, action
| filter dstaddr like /^52.94./ or dstaddr like /^52.119./
| stats count() as requests by srcaddr, action
| sort requests desc


Note: DynamoDB uses AWS IP ranges (prefix lists). Check current ranges with:
bash
aws ec2 describe-prefix-lists --region us-east-1 \
  --filters "Name=prefix-list-name,Values=com.amazonaws.us-east-1.dynamodb"


### 3. Rejected Traffic (Security Issues)
sql
fields @timestamp, srcaddr, dstaddr, srcport, dstport, protocol
| filter action = "REJECT"
| stats count() as rejections by srcaddr, dstaddr, dstport
| sort rejections desc
| limit 50


### 4. Traffic Between ALB and EC2
sql
fields @timestamp, srcaddr, dstaddr, srcport, dstport, bytes
| filter (srcaddr like "10.0.1." and dstaddr like "10.0.2.") 
     or (srcaddr like "10.0.2." and dstaddr like "10.0.1.")
| stats sum(bytes) as totalBytes by srcaddr, dstaddr
| sort totalBytes desc


### 5. Traffic to RDS PostgreSQL (Port 5432)
sql
fields @timestamp, srcaddr, dstaddr, bytes, action
| filter dstport = 5432 or srcport = 5432
| stats sum(bytes) as totalBytes, count() as connections by srcaddr, dstaddr, action
| sort totalBytes desc


### 6. Top Destination Ports (Service Discovery)
sql
fields @timestamp, dstport, protocol
| filter action = "ACCEPT"
| stats count() as connections by dstport, protocol
| sort connections desc
| limit 20


### 7. Traffic Volume Over Time
sql
fields @timestamp, bytes
| stats sum(bytes) as totalBytes by bin(5m)
| sort @timestamp desc


### 8. Outbound Internet Traffic (NAT Gateway)
sql
fields @timestamp, srcaddr, dstaddr, dstport, bytes
| filter dstaddr not like /^10\./ and dstaddr not like /^172\.16\./ and dstaddr not like /^192\.168\./
| stats sum(bytes) as totalBytes by srcaddr, dstport
| sort totalBytes desc
| limit 20


### 9. Failed Connection Attempts
sql
fields @timestamp, srcaddr, dstaddr, dstport, protocol
| filter action = "REJECT" and (protocol = "6" or protocol = "17")
| stats count() as attempts by srcaddr, dstaddr, dstport
| sort attempts desc
| limit 30


### 10. Specific EC2 Instance Traffic
sql
fields @timestamp, srcaddr, dstaddr, srcport, dstport, bytes, action
| filter srcaddr = "10.0.2.15" or dstaddr = "10.0.2.15"
| stats sum(bytes) as totalBytes by srcaddr, dstaddr, dstport
| sort totalBytes desc