## Do 2 Lambda Functions Share ENIs?

### Short Answer

It depends on their VPC configuration.

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━


## Scenario 1: Same Subnets + Same Security Groups

YES - They share ENIs

bash
# Lambda Function 1
aws lambda create-function \
  --function-name function-1 \
  --vpc-config SubnetIds=subnet-a,subnet-b,SecurityGroupIds=sg-lambda

# Lambda Function 2
aws lambda create-function \
  --function-name function-2 \
  --vpc-config SubnetIds=subnet-a,subnet-b,SecurityGroupIds=sg-lambda

Result: Both functions share the same ENIs


Why: ENIs are created per subnet + security group combination, NOT per Lambda function.

Example:
subnet-a + sg-lambda → ENI-1 (shared by function-1 and function-2)
subnet-b + sg-lambda → ENI-2 (shared by function-1 and function-2)

Total ENIs: 2 (shared)


━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━


## Scenario 2: Different Security Groups

NO - They use separate ENIs

bash
# Lambda Function 1
aws lambda create-function \
  --function-name function-1 \
  --vpc-config SubnetIds=subnet-a,subnet-b,SecurityGroupIds=sg-lambda-1

# Lambda Function 2
aws lambda create-function \
  --function-name function-2 \
  --vpc-config SubnetIds=subnet-a,subnet-b,SecurityGroupIds=sg-lambda-2

Result: Each function uses separate ENIs


Example:
Function 1:
├── subnet-a + sg-lambda-1 → ENI-1
└── subnet-b + sg-lambda-1 → ENI-2

Function 2:
├── subnet-a + sg-lambda-2 → ENI-3
└── subnet-b + sg-lambda-2 → ENI-4

Total ENIs: 4 (separate)


━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━


## Scenario 3: Different Subnets

PARTIAL - They share some ENIs

bash
# Lambda Function 1
aws lambda create-function \
  --function-name function-1 \
  --vpc-config SubnetIds=subnet-a,SecurityGroupIds=sg-lambda

# Lambda Function 2
aws lambda create-function \
  --function-name function-2 \
  --vpc-config SubnetIds=subnet-b,SecurityGroupIds=sg-lambda

Result: Each function uses separate ENIs (different subnets)


Example:
Function 1:
└── subnet-a + sg-lambda → ENI-1

Function 2:
└── subnet-b + sg-lambda → ENI-2

Total ENIs: 2 (separate)


━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━


## Scenario 4: Overlapping Subnets

YES - They share ENIs for overlapping combinations

bash
# Lambda Function 1
aws lambda create-function \
  --function-name function-1 \
  --vpc-config SubnetIds=subnet-a,subnet-b,SecurityGroupIds=sg-lambda

# Lambda Function 2
aws lambda create-function \
  --function-name function-2 \
  --vpc-config SubnetIds=subnet-b,subnet-c,SecurityGroupIds=sg-lambda

Result: They share ENI in subnet-b


Example:
Function 1:
├── subnet-a + sg-lambda → ENI-1 (function-1 only)
└── subnet-b + sg-lambda → ENI-2 (shared)

Function 2:
├── subnet-b + sg-lambda → ENI-2 (shared)
└── subnet-c + sg-lambda → ENI-3 (function-2 only)

Total ENIs: 3 (1 shared, 2 separate)


━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━


## Visual Examples

### Example 1: Shared ENIs

Configuration:
Function-1: subnet-a, subnet-b, sg-lambda
Function-2: subnet-a, subnet-b, sg-lambda

ENI Layout:
┌─────────────────────────────────────┐
│ subnet-a + sg-lambda                │
│ ENI-1                               │
│ ├── Function-1 executions          │
│ └── Function-2 executions          │
└─────────────────────────────────────┘

┌─────────────────────────────────────┐
│ subnet-b + sg-lambda                │
│ ENI-2                               │
│ ├── Function-1 executions          │
│ └── Function-2 executions          │
└─────────────────────────────────────┘

Total: 2 ENIs (both shared)


### Example 2: Separate ENIs

Configuration:
Function-1: subnet-a, subnet-b, sg-lambda-1
Function-2: subnet-a, subnet-b, sg-lambda-2

ENI Layout:
┌─────────────────────────────────────┐
│ subnet-a + sg-lambda-1              │
│ ENI-1                               │
│ └── Function-1 executions only     │
└─────────────────────────────────────┘

┌─────────────────────────────────────┐
│ subnet-b + sg-lambda-1              │
│ ENI-2                               │
│ └── Function-1 executions only     │
└─────────────────────────────────────┘

┌─────────────────────────────────────┐
│ subnet-a + sg-lambda-2              │
│ ENI-3                               │
│ └── Function-2 executions only     │
└─────────────────────────────────────┘

┌─────────────────────────────────────┐
│ subnet-b + sg-lambda-2              │
│ ENI-4                               │
│ └── Function-2 executions only     │
└─────────────────────────────────────┘

Total: 4 ENIs (all separate)


━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━


## How to Verify

### Check ENI Sharing

bash
# List all Lambda ENIs with details
aws ec2 describe-network-interfaces \
  --filters Name=description,Values="AWS Lambda VPC ENI*" \
  --query 'NetworkInterfaces[*].[NetworkInterfaceId,SubnetId,Groups[0].GroupId,PrivateIpAddress]' \
  --output table

# Output:
# eni-abc123  subnet-a  sg-lambda  10.0.1.45
# eni-def456  subnet-b  sg-lambda  10.0.2.67
# eni-ghi789  subnet-a  sg-other   10.0.1.89


If two Lambda functions have:
- Same subnet ID
- Same security group ID

Then they share that ENI.

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━


## Best Practices

### 1. Share ENIs When Possible (Cost & Efficiency)

bash
# ✅ Good: All functions use same VPC config
aws lambda create-function --function-name func-1 \
  --vpc-config SubnetIds=subnet-a,subnet-b,SecurityGroupIds=sg-lambda

aws lambda create-function --function-name func-2 \
  --vpc-config SubnetIds=subnet-a,subnet-b,SecurityGroupIds=sg-lambda

aws lambda create-function --function-name func-3 \
  --vpc-config SubnetIds=subnet-a,subnet-b,SecurityGroupIds=sg-lambda

# Result: All 3 functions share 2 ENIs
# Efficient use of IPs


### 2. Separate ENIs When Needed (Security)

bash
# ✅ Good: Separate security groups for different access levels
aws lambda create-function --function-name public-api \
  --vpc-config SubnetIds=subnet-a,subnet-b,SecurityGroupIds=sg-public

aws lambda create-function --function-name admin-api \
  --vpc-config SubnetIds=subnet-a,subnet-b,SecurityGroupIds=sg-admin

# Result: Separate ENIs for different security contexts


━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━


## Real-World Example

### Microservices Architecture

bash
# User Service
aws lambda create-function --function-name user-service \
  --vpc-config SubnetIds=subnet-a,subnet-b,SecurityGroupIds=sg-app

# Order Service
aws lambda create-function --function-name order-service \
  --vpc-config SubnetIds=subnet-a,subnet-b,SecurityGroupIds=sg-app

# Payment Service
aws lambda create-function --function-name payment-service \
  --vpc-config SubnetIds=subnet-a,subnet-b,SecurityGroupIds=sg-app

# All connect to same RDS
# All use same security group


ENI Usage:
subnet-a + sg-app → ENI-1
├── user-service executions
├── order-service executions
└── payment-service executions

subnet-b + sg-app → ENI-2
├── user-service executions
├── order-service executions
└── payment-service executions

Total: 2 ENIs (shared by all 3 functions)


Benefits:
- Efficient IP usage
- Fewer ENIs to manage
- Consistent network configuration

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━


## Summary

### ENI Sharing Rules

| Configuration | Shared ENIs? |
|---------------|--------------|
| Same subnets + Same SGs | ✅ Yes (fully shared) |
| Same subnets + Different SGs | ❌ No (separate) |
| Different subnets + Same SGs | ❌ No (separate) |
| Overlapping subnets + Same SGs | ⚠️ Partial (shared for overlapping) |

### Key Formula

ENI is shared if and only if:
Subnet ID + Security Group ID combination is identical


### Practical Guidance

To share ENIs (recommended):
- Use same VPC configuration across Lambda functions
- Use same security group
- Use same subnets

To separate ENIs (when needed):
- Use different security groups
- Or use different subnets

Bottom line: ENIs are shared based on subnet + security group combination, NOT per Lambda function. Multiple Lambda functions 
with identical VPC configurations will share the same ENIs.