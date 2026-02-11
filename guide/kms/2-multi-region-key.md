## Benefits of Multi-Region Keys

### 1. Disaster Recovery & Business Continuity
- Encrypt data in one region, decrypt in another without re-encryption
- Failover to secondary region without key management complexity
- Same key ID works across regions

### 2. Low Latency Access
- Applications access local replica instead of cross-region calls
- Reduces latency from ~50-100ms to <10ms
- Better performance for encryption-heavy workloads

### 3. Data Portability
- Copy encrypted data between regions without decryption
- S3 cross-region replication with same key
- EBS snapshots can be copied and used in other regions

### 4. Simplified Key Management
- Single key ID across all regions
- Centralized key policies and aliases
- Automatic synchronization of key material

### 5. Compliance & Data Residency
- Meet regional data sovereignty requirements
- Keep key replicas in required jurisdictions
- Audit trail in each region

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━


## Common Use Cases

### Use Case 1: Multi-Region Application with S3

Scenario:
- Application runs in us-east-1 and ap-southeast-1
- S3 buckets in both regions with encrypted data
- Need to access data from either region

Without Multi-Region Keys:
Problem: Data encrypted in us-east-1 with regional key
→ Cannot decrypt in ap-southeast-1 without cross-region KMS calls
→ High latency + cross-region data transfer costs


With Multi-Region Keys:
Solution: Use multi-region key
→ Primary in us-east-1, replica in ap-southeast-1
→ Each region accesses local KMS replica
→ Low latency, no cross-region KMS calls


━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━


### Use Case 2: Disaster Recovery

Scenario:
- Primary application in us-east-1
- DR site in ap-southeast-1
- Need to failover quickly during outage

Architecture:
Normal Operation:
EC2 (us-east-1) → S3 (us-east-1) → KMS Primary (us-east-1)

Disaster Failover:
EC2 (ap-southeast-1) → S3 (ap-southeast-1) → KMS Replica (ap-southeast-1)
                    ↓
            S3 Cross-Region Replication
            (encrypted data copied automatically)


Benefits:
- No need to re-encrypt data during failover
- Same key ID in application configuration
- RTO/RPO improvements (minutes vs hours)

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━


### Use Case 3: Global Data Processing

Scenario:
- Data ingested in multiple regions
- Centralized data lake in S3
- Analytics workloads run regionally

Flow:
Region 1: Ingest → Encrypt with multi-region key → S3
Region 2: Ingest → Encrypt with same key → S3
Region 3: Analytics reads from any region's S3 → Decrypt locally


━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━


## EC2 to S3 with KMS - Common Scenarios

### Scenario 1: Single-Region Setup

Architecture:
EC2 (us-east-1)
  ↓
  1. GetObject from S3
  2. S3 calls KMS Decrypt (automatic)
  3. Returns decrypted data to EC2
  ↓
S3 Bucket (us-east-1, SSE-KMS enabled)
  ↓
KMS Key (us-east-1)


IAM Policy Required:
json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "s3:GetObject",
        "s3:PutObject"
      ],
      "Resource": "arn:aws:s3:::my-bucket/*"
    },
    {
      "Effect": "Allow",
      "Action": [
        "kms:Decrypt",
        "kms:GenerateDataKey"
      ],
      "Resource": "arn:aws:kms:us-east-1:123456789012:key/key-id"
    }
  ]
}


Cost:
- S3 API calls: Standard S3 pricing
- KMS API calls: Automatic (S3 calls KMS), included in free tier

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━


### Scenario 2: Multi-Region with Cross-Region Replication

Architecture:
Primary Region (us-east-1):
EC2 → S3 Bucket (SSE-KMS) → KMS Primary Key

Cross-Region Replication:
S3 (us-east-1) → S3 (ap-southeast-1)
  ↓
Uses same multi-region key

Secondary Region (ap-southeast-1):
EC2 → S3 Bucket (SSE-KMS) → KMS Replica Key


S3 Replication Configuration:
json
{
  "Role": "arn:aws:iam::123456789012:role/s3-replication-role",
  "Rules": [
    {
      "Status": "Enabled",
      "Priority": 1,
      "Filter": {},
      "Destination": {
        "Bucket": "arn:aws:s3:::my-bucket-replica",
        "ReplicaKmsKeyID": "arn:aws:kms:ap-southeast-1:123456789012:key/mrk-same-key-id",
        "EncryptionConfiguration": {
          "ReplicaKmsKeyID": "ar Same key ID works across regionsn:aws:kms:ap-southeast-1:123456789012:key/mrk-same-key-id"
        }
      }
    }
  ]
}


Benefits:
- Data automatically encrypted in destination with replica key
- No re-encryption needed
- EC2 in ap-southeast-1 can decrypt locally

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━


### Scenario 3: Cross-Region Data Access

Without Multi-Region Key:
EC2 (ap-southeast-1) needs data from S3 (us-east-1)
  ↓
  1. GetObject from S3 us-east-1
  2. S3 calls KMS Decrypt in us-east-1 (cross-region)
  3. High latency (~100ms for KMS call)
  4. Cross-region data transfer charges


With Multi-Region Key:
Option A: Access local replica
EC2 (ap-southeast-1) → S3 (ap-southeast-1) → KMS Replica (ap-southeast-1)
  ↓ Low latency

Option B: Access remote with local decrypt
EC2 (ap-southeast-1) → S3 (us-east-1) → KMS Replica (ap-southeast-1)
  ↓ S3 data transfer, but KMS decrypt is local


━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━


## Key Rotation

### Automatic Key Rotation

Single-Region Key:
Enable automatic rotation: Rotates annually
→ New cryptographic material
→ Old material retained for decryption
→ Transparent to applications


Multi-Region Key:
Enable rotation on primary key
→ Automatically rotates all replicas
→ Synchronized across regions
→ Same rotation schedule everywhere


Enable via CLI:
bash
aws kms enable-key-rotation \
  --key-id mrk-1234abcd5678ef90 \
  --region us-east-1


Check rotation status:
bash
aws kms get-key-rotation-status \
  --key-id mrk-1234abcd5678ef90 \
  --region us-east-1


Important:
- Rotation happens automatically every 365 days
- AWS manages the rotation
- No application changes needed
- Old key material never deleted (for decryption)

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━


### Manual Key Rotation (Change Key, Keep Alias)

Scenario: Need to rotate to a new key immediately (security incident, compliance)

Steps:

1. Create new multi-region key:
bash
# Create primary in us-east-1
aws kms create-key \
  --description "New multi-region key" \
  --multi-region \
  --region us-east-1

# Output: mrk-new-key-id

# Create replica in ap-southeast-1
aws kms replicate-key \
  --key-id mrk-new-key-id \
  --replica-region ap-southeast-1 \
  --region us-east-1


2. Update alias to point to new key:
bash
# Update alias in us-east-1
aws kms update-alias \
  --alias-name alias/my-app-key \
  --target-key-id mrk-new-key-id \
  --region us-east-1

# Update alias in ap-southeast-1
aws kms update-alias \
  --alias-name alias/my-app-key \
  --target-key-id mrk-new-key-id \
  --region ap-southeast-1


3. Update application configuration (if using key ID):
python
# Before (hardcoded key ID)
kms_key_id = "arn:aws:kms:us-east-1:123456789012:key/mrk-old-key-id"

# After (use alias - recommended)
kms_key_id = "alias/my-app-key"


4. Re-encrypt existing data (optional but recommended):
bash
# For S3 objects
aws s3 cp s3://my-bucket/ s3://my-bucket/ \
  --recursive \
  --sse aws:kms \
  --sse-kms-key-id alias/my-app-key \
  --metadata-directive REPLACE


5. Disable old key after verification:
bash
# Disable (can re-enable if needed)
aws kms disable-key \
  --key-id mrk-old-key-id \
  --region us-east-1

# Schedule deletion (7-30 days waiting period)
aws kms schedule-key-deletion \
  --key-id mrk-old-key-id \
  --pending-window-in-days 30 \
  --region us-east-1


Benefits of using aliases:
- Applications reference alias, not key ID
- Update alias to point to new key
- No application code changes
- Gradual migration possible

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━


## Best Practices for Multi-Region Keys

### 1. Use Aliases for Application References

Bad:
python
# Hardcoded key ID
kms_key = "arn:aws:kms:us-east-1:123456789012:key/mrk-1234"


Good:
python
# Use alias
kms_key = "alias/my-app-key"

# Or region-agnostic
import boto3
region = boto3.session.Session().region_name
kms_key = f"alias/my-app-key"  # Same alias in all regions


### 2. Implement Least Privilege IAM Policies

json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "AllowEncryptDecrypt",
      "Effect": "Allow",
      "Action": [
        "kms:Decrypt",
        "kms:GenerateDataKey",
        "kms:DescribeKey"
      ],
      "Resource": "arn:aws:kms:*:123456789012:key/mrk-*",
      "Condition": {
        "StringEquals": {
          "kms:ViaService": [
            "s3.us-east-1.amazonaws.com",
            "s3.ap-southeast-1.amazonaws.com"
          ]
        }
      }
    }
  ]
}


### 3. Enable Key Rotation

bash
# Enable on primary (applies to all replicas)
aws kms enable-key-rotation \
  --key-id mrk-1234abcd5678ef90 \
  --region us-east-1


### 4. Use Key Policies for Cross-Account Access

json
{
  "Sid": "Allow cross-account use",
  "Effect": "Allow",
  "Principal": {
    "AWS": "arn:aws:iam::999999999999:root"
  },
  "Action": [
    "kms:Decrypt",
    "kms:DescribeKey"
  ],
  "Resource": "*",
  "Condition": {
    "StringEquals": {
      "kms:ViaService": "s3.us-east-1.amazonaws.com"
    }
  }
}


### 5. Monitor Key Usage

bash
# CloudWatch Logs for KMS API calls
# Enable CloudTrail for audit

# Monitor metrics
aws cloudwatch get-metric-statistics \
  --namespace AWS/KMS \
  --metric-name NumberOfDecryptCalls \
  --dimensions Name=KeyId,Value=mrk-1234 \
  --start-time 2026-02-10T00:00:00Z \
  --end-time 2026-02-11T00:00:00Z \
  --period 3600 \
  --statistics Sum


### 6. Tag Keys for Cost Allocation

bash
aws kms tag-resource \
  --key-id mrk-1234abcd5678ef90 \
  --tags TagKey=Environment,TagValue=Production \
         TagKey=Application,TagValue=MyApp \
         TagKey=CostCenter,TagValue=Engineering \
  --region us-east-1


### 7. Document Key Purpose and Ownership

bash
aws kms update-key-description \
  --key-id mrk-1234abcd5678ef90 \
  --description "Multi-region key for MyApp S3 encryption. Owner: platform-team@company.com" \
  --region us-east-1


### 8. Test Failover Scenarios

bash
# Simulate primary region failure
# 1. Disable primary key (testing only)
aws kms disable-key --key-id mrk-1234 --region us-east-1

# 2. Verify application can use replica
aws kms decrypt \
  --ciphertext-blob fileb://encrypted.dat \
  --key-id mrk-1234 \
  --region ap-southeast-1

# 3. Re-enable primary
aws kms enable-key --key-id mrk-1234 --region us-east-1


### 9. Use Envelope Encryption

python
import boto3
import os

kms = boto3.client('kms')
s3 = boto3.client('s3')

# Generate data key (envelope encryption)
response = kms.generate_data_key(
    KeyId='alias/my-app-key',
    KeySpec='AES_256'
)

plaintext_key = response['Plaintext']
encrypted_key = response['CiphertextBlob']

# Encrypt data with data key (client-side)
# Store encrypted_key with data
# Decrypt data key with KMS when needed


Benefits:
- Reduces KMS API calls
- Better performance
- Lower costs

### 10. Implement Key Deletion Protection

bash
# Never delete immediately
# Always use pending window

aws kms schedule-key-deletion \
  --key-id mrk-1234 \
  --pending-window-in-days 30 \
  --region us-east-1

# Cancel if needed
aws kms cancel-key-deletion \
  --key-id mrk-1234 \
  --region us-east-1


### 11. Separate Keys by Environment

Production: alias/prod-app-key (multi-region)
Staging: alias/staging-app-key (single-region)
Development: alias/dev-app-key (single-region)


### 12. Use VPC Endpoints for KMS

bash
# Reduces data transfer costs
# Improves security (private connectivity)

aws ec2 create-vpc-endpoint \
  --vpc-id vpc-12345678 \
  --service-name com.amazonaws.us-east-1.kms \
  --route-table-ids rtb-12345678 \
  --subnet-ids subnet-12345678 subnet-87654321


━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━


## Complete Example: Multi-Region Application

### Architecture

Primary Region (us-east-1):
- EC2 Auto Scaling Group
- S3 Bucket (SSE-KMS)
- KMS Multi-Region Primary Key
- RDS (encrypted with KMS)

Secondary Region (ap-southeast-1):
- EC2 Auto Scaling Group (standby)
- S3 Bucket (replication target)
- KMS Multi-Region Replica Key
- RDS Read Replica (encrypted with replica key)


### Setup Steps

1. Create multi-region key:
bash
# Primary
PRIMARY_KEY=$(aws kms create-key \
  --description "MyApp multi-region key" \
  --multi-region \
  --region us-east-1 \
  --query 'KeyMetadata.KeyId' \
  --output text)

# Replica
aws kms replicate-key \
  --key-id $PRIMARY_KEY \
  --replica-region ap-southeast-1 \
  --region us-east-1

# Create aliases
aws kms create-alias \
  --alias-name alias/myapp-key \
  --target-key-id $PRIMARY_KEY \
  --region us-east-1

aws kms create-alias \
  --alias-name alias/myapp-key \
  --target-key-id $PRIMARY_KEY \
  --region ap-southeast-1


2. Enable rotation:
bash
aws kms enable-key-rotation \
  --key-id $PRIMARY_KEY \
  --region us-east-1


3. Configure S3 buckets:
bash
# Primary bucket
aws s3api create-bucket \
  --bucket myapp-primary \
  --region us-east-1

aws s3api put-bucket-encryption \
  --bucket myapp-primary \
  --server-side-encryption-configuration '{
    "Rules": [{
      "ApplyServerSideEncryptionByDefault": {
        "SSEAlgorithm": "aws:kms",
        "KMSMasterKeyID": "alias/myapp-key"
      }
    }]
  }'

# Replica bucket
aws s3api create-bucket \
  --bucket myapp-replica \
  --region ap-southeast-1 \
  --create-bucket-configuration LocationConstraint=ap-southeast-1

aws s3api put-bucket-encryption \
  --bucket myapp-replica \
  --server-side-encryption-configuration '{
    "Rules": [{
      "ApplyServerSideEncryptionByDefault": {
        "SSEAlgorithm": "aws:kms",
        "KMSMasterKeyID": "alias/myapp-key"
      }
    }]
  }'

# Enable replication
aws s3api put-bucket-replication \
  --bucket myapp-primary \
  --replication-configuration file://replication.json


4. Application code (region-agnostic):
python
import boto3
import os

# Automatically uses correct region
region = os.environ.get('AWS_REGION', 'us-east-1')
s3 = boto3.client('s3', region_name=region)
kms = boto3.client('kms', region_name=region)

# Use alias (works in all regions)
def upload_encrypted_file(bucket, key, data):
    s3.put_object(
        Bucket=bucket,
        Key=key,
        Body=data,
        ServerSideEncryption='aws:kms',
        SSEKMSKeyId='alias/myapp-key'
    )

def download_encrypted_file(bucket, key):
    response = s3.get_object(Bucket=bucket, Key=key)
    return response['Body'].read()


━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━


## Summary

Use Multi-Region Keys When:
- Running applications in multiple regions
- Need disaster recovery with fast failover
- Cross-region data replication required
- Low latency encryption/decryption needed globally
- Compliance requires regional key availability

Best Practices:
1. Use aliases, not key IDs
2. Enable automatic rotation
3. Implement least privilege IAM
4. Monitor usage with CloudTrail
5. Test failover scenarios
6. Use envelope encryption for performance
7. Separate keys by environment
8. Document key ownership
9. Use VPC endpoints
10. Never delete keys immediately

Cost Consideration:
- $1/month per replica
- Worth it for production multi-region applications
- Not worth it for single-region or low-volume workloads