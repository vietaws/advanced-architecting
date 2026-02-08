## Lambda Scaling in VPC and ENI Usage

### How Lambda Scales in VPC

Lambda creates ENIs (Elastic Network Interfaces) to connect to your VPC.

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━


## ENI Creation Model

### Key Concept: Hyperplane ENIs

Lambda uses a shared ENI model called "Hyperplane"

Old Model (before 2019):
- 1 ENI per Lambda execution environment
- Slow scaling (ENI creation took 10-90 seconds)

New Model (Hyperplane, after 2019):
- Shared ENIs across multiple Lambda execution environments
- Fast scaling (<1 second)
- Fewer ENIs needed


━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━


## How Many ENIs Are Created?

### Formula

ENIs are created based on:
1. Number of unique subnet + security group combinations
2. Network traffic demand

Not based on:
- ❌ Number of concurrent Lambda executions
- ❌ Number of Lambda invocations

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━


## ENI Scaling Examples

### Example 1: Single Subnet + Single Security Group

Lambda Configuration:
- Subnets: [subnet-a]
- Security Groups: [sg-lambda]

Scaling:
- 1 concurrent execution → 1 ENI
- 10 concurrent executions → 1 ENI (shared)
- 100 concurrent executions → 1-2 ENIs (shared)
- 1000 concurrent executions → 2-5 ENIs (shared)

Key: Multiple Lambda executions share the same ENI


### Example 2: Multiple Subnets + Single Security Group

Lambda Configuration:
- Subnets: [subnet-a, subnet-b]
- Security Groups: [sg-lambda]

Scaling:
- 1 concurrent execution → 1 ENI (in subnet-a or subnet-b)
- 100 concurrent executions → 2-4 ENIs (distributed across subnets)
- 1000 concurrent executions → 4-10 ENIs (distributed across subnets)

Key: ENIs created in each subnet as needed


### Example 3: Multiple Subnets + Multiple Security Groups

Lambda Configuration:
- Subnets: [subnet-a, subnet-b]
- Security Groups: [sg-lambda-1, sg-lambda-2]

Scaling:
- ENIs created for each combination:
  - subnet-a + sg-lambda-1
  - subnet-a + sg-lambda-2
  - subnet-b + sg-lambda-1
  - subnet-b + sg-lambda-2
- Minimum: 4 ENIs (one per combination)
- At scale: 8-20 ENIs


━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━


## Real-World Scaling Scenario

### Scenario: E-commerce Application

Configuration:
bash
aws lambda create-function \
  --function-name order-processor \
  --vpc-config SubnetIds=subnet-a,subnet-b,SecurityGroupIds=sg-lambda


Traffic Pattern:
Time: 00:00 - 1 request/second
├── Concurrent executions: 1
├── ENIs created: 1
└── ENI location: subnet-a

Time: 12:00 - 10 requests/second
├── Concurrent executions: 10
├── ENIs created: 1-2
└── ENI locations: subnet-a, subnet-b

Time: 18:00 (peak) - 100 requests/second
├── Concurrent executions: 100
├── ENIs created: 2-4
└── ENI locations: distributed across subnet-a, subnet-b

Time: 20:00 (Black Friday) - 1000 requests/second
├── Concurrent executions: 1000
├── ENIs created: 5-10
└── ENI locations: distributed across subnet-a, subnet-b


━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━


## ENI Lifecycle

### Creation

1. First Lambda invocation in VPC
   ↓
2. Lambda service creates ENI in your subnet
   ↓
3. ENI gets private IP from subnet CIDR
   ↓
4. ENI attached to Lambda execution environment
   ↓
5. Lambda can now access VPC resources
   
Time: <1 second (Hyperplane model)


### Reuse

1. Lambda execution completes
   ↓
2. ENI remains in VPC (not deleted)
   ↓
3. Next Lambda invocation reuses same ENI
   ↓
4. Multiple Lambda executions share ENI
   
Result: Fast subsequent invocations


### Deletion

1. Lambda function deleted or VPC config removed
   ↓
2. Lambda service waits for all executions to complete
   ↓
3. ENIs marked for deletion
   ↓
4. ENIs deleted after ~20 minutes
   
Note: ENIs are NOT deleted immediately


━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━


## Check ENI Usage

### View Lambda ENIs

bash
# List all Lambda ENIs
aws ec2 describe-network-interfaces \
  --filters Name=description,Values="AWS Lambda VPC ENI*" \
  --query 'NetworkInterfaces[*].[NetworkInterfaceId,PrivateIpAddress,Status,SubnetId]' \
  --output table

# Output:
# eni-abc123  10.0.1.45   in-use  subnet-a
# eni-def456  10.0.2.67   in-use  subnet-b
# eni-ghi789  10.0.1.89   in-use  subnet-a


### View ENIs for Specific Lambda

bash
# Get Lambda function details
aws lambda get-function-configuration \
  --function-name order-processor \
  --query 'VpcConfig'

# Find ENIs in Lambda's subnets and security groups
SUBNET_A="subnet-xxxxx"
SG_LAMBDA="sg-xxxxx"

aws ec2 describe-network-interfaces \
  --filters \
    Name=subnet-id,Values=$SUBNET_A \
    Name=group-id,Values=$SG_LAMBDA \
    Name=description,Values="AWS Lambda VPC ENI*" \
  --query 'NetworkInterfaces[*].[NetworkInterfaceId,PrivateIpAddress,Status]'


━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━


## ENI Limits and Quotas

### AWS Account Limits

Default ENI limit per region: 5,000
Default private IPs per ENI: 50

Check your limits:
aws ec2 describe-account-attributes \
  --attribute-names max-elastic-ips \
  --query 'AccountAttributes[*].AttributeValues'


### Subnet IP Address Exhaustion

Problem:
Subnet CIDR: 10.0.1.0/24 (256 IPs)
Reserved by AWS: 5 IPs
Available: 251 IPs

If Lambda creates 10 ENIs:
- 10 IPs used by Lambda
- 241 IPs remaining for other resources


Solution: Use larger subnets for Lambda
bash
# Instead of /24 (256 IPs)
# Use /20 (4,096 IPs)
aws ec2 create-subnet \
  --vpc-id $VPC_ID \
  --cidr-block 10.0.0.0/20 \
  --availability-zone us-east-1a


━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━


## Scaling Patterns

### Pattern 1: Gradual Scale-Up

Time    Requests/sec    Concurrent    ENIs
00:00   1               1             1
00:10   5               5             1
00:20   10              10            1-2
00:30   50              50            2-3
00:40   100             100           3-5
00:50   500             500           5-10
01:00   1000            1000          8-15


### Pattern 2: Sudden Spike

Time    Requests/sec    Concurrent    ENIs    Notes
00:00   10              10            2       Normal
00:01   1000            1000          2       Spike! ENIs insufficient
00:02   1000            1000          5       Lambda creates more ENIs
00:03   1000            1000          10      Fully scaled
00:04   1000            1000          10      Stable


During spike (00:01-00:02):
- Some requests may experience cold start
- ENIs created on-demand
- Scaling completes in 1-2 seconds

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━


## Best Practices

### 1. Use Multiple Subnets (High Availability)

bash
# ✅ Good: 2 subnets in different AZs
aws lambda update-function-configuration \
  --function-name my-function \
  --vpc-config SubnetIds=subnet-a,subnet-b,SecurityGroupIds=sg-lambda

# ❌ Bad: 1 subnet (single point of failure)
aws lambda update-function-configuration \
  --function-name my-function \
  --vpc-config SubnetIds=subnet-a,SecurityGroupIds=sg-lambda


### 2. Use Large Subnets

bash
# ✅ Good: /20 subnet (4,096 IPs)
aws ec2 create-subnet \
  --cidr-block 10.0.0.0/20

# ❌ Bad: /28 subnet (16 IPs - only 11 usable)
aws ec2 create-subnet \
  --cidr-block 10.0.1.0/28


### 3. Minimize Security Group Combinations

bash
# ✅ Good: 1 security group
--vpc-config SubnetIds=subnet-a,subnet-b,SecurityGroupIds=sg-lambda

# ❌ Bad: Multiple security groups (more ENIs)
--vpc-config SubnetIds=subnet-a,subnet-b,SecurityGroupIds=sg-1,sg-2,sg-3


### 4. Use Provisioned Concurrency for Predictable Load

bash
# Pre-warm Lambda with provisioned concurrency
aws lambda put-provisioned-concurrency-config \
  --function-name order-processor \
  --provisioned-concurrent-executions 10

# ENIs created immediately, no cold start


━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━


## Monitoring ENI Usage

### CloudWatch Metrics

bash
# Monitor concurrent executions
aws cloudwatch get-metric-statistics \
  --namespace AWS/Lambda \
  --metric-name ConcurrentExecutions \
  --dimensions Name=FunctionName,Value=order-processor \
  --start-time 2026-02-09T00:00:00Z \
  --end-time 2026-02-09T01:00:00Z \
  --period 60 \
  --statistics Maximum

# Monitor ENI count (custom metric)
aws ec2 describe-network-interfaces \
  --filters Name=description,Values="AWS Lambda VPC ENI*" \
  --query 'length(NetworkInterfaces)'


### Lambda Insights

bash
# Enable Lambda Insights
aws lambda update-function-configuration \
  --function-name order-processor \
  --layers arn:aws:lambda:us-east-1:580247275435:layer:LambdaInsightsExtension:14


━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━


## Troubleshooting

### Problem 1: Insufficient IP Addresses

Error: "ENI creation failed: Insufficient IP addresses in subnet"

Solution:
1. Use larger subnet (/20 instead of /24)
2. Or use different subnet with more IPs


### Problem 2: ENI Limit Exceeded

Error: "ENI limit exceeded"

Solution:
1. Request limit increase from AWS Support
2. Or reduce number of subnet + security group combinations


### Problem 3: Slow Scaling

Symptom: Cold starts during traffic spikes

Solution:
1. Use provisioned concurrency
2. Or use reserved concurrency to pre-warm


━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━


## Summary

### ENI Scaling Rules

| Scenario | ENIs Created |
|----------|--------------|
| 1 subnet, 1 SG, 10 concurrent | 1-2 ENIs |
| 2 subnets, 1 SG, 10 concurrent | 1-2 ENIs |
| 2 subnets, 1 SG, 100 concurrent | 2-4 ENIs |
| 2 subnets, 1 SG, 1000 concurrent | 5-10 ENIs |
| 2 subnets, 2 SGs, 1000 concurrent | 10-20 ENIs |

### Key Points

1. ENIs are shared across multiple Lambda executions
2. ENIs scale automatically based on traffic
3. 1 ENI ≠ 1 Lambda execution (many-to-one relationship)
4. ENIs are reused across invocations
5. More subnets/SGs = More ENIs needed
6. Hyperplane model makes scaling fast (<1 second)
7. ENIs persist even after Lambda executions complete

Bottom line: Lambda creates as few ENIs as possible and shares them across many executions. You typically need 5-15 ENIs even 
for 1000+ concurrent executions.