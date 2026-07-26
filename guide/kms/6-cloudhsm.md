## Custom Key Store (CloudHSM) Explained

### What is Custom Key Store?

Custom Key Store = KMS keys stored in YOUR CloudHSM cluster instead of AWS-managed HSMs

Standard KMS:
Application → KMS → AWS-Managed HSM (shared, multi-tenant)

Custom Key Store:
Application → KMS → Your CloudHSM Cluster (dedicated, single-tenant)


━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━


## Relationship to Symmetric/Asymmetric

Custom Key Store supports BOTH symmetric and asymmetric keys.

The choice of CloudHSM vs standard KMS is independent from symmetric vs asymmetric:

| | Standard KMS | Custom Key Store (CloudHSM) |
|---|---|---|
| Symmetric Keys | ✅ Yes | ✅ Yes |
| Asymmetric Keys | ✅ Yes | ✅ Yes |
| Hardware | AWS-managed (shared) | Your CloudHSM (dedicated) |
| Control | AWS controls HSM | You control HSM |
| Compliance | FIPS 140-2 Level 2 | FIPS 140-2 Level 3 |

Key Point: CloudHSM is about WHERE keys are stored, not WHAT TYPE of keys.

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━


## Benefits of Custom Key Store (CloudHSM)

### 1. Full Hardware Control

Standard KMS:
Your keys stored in AWS-managed HSM
├── Shared hardware (multi-tenant)
├── AWS manages hardware
└── You trust AWS


Custom Key Store:
Your keys stored in YOUR CloudHSM cluster
├── Dedicated hardware (single-tenant)
├── You manage hardware
└── You control everything


### 2. FIPS 140-2 Level 3 Compliance

Standard KMS:
- FIPS 140-2 Level 2 (software-level security)

CloudHSM:
- FIPS 140-2 Level 3 (hardware-level security)
- Tamper-evident physical security
- Required for some regulations (PCI-DSS Level 1, government)

### 3. Key Material Never Leaves HSM

Standard KMS:
Key material in AWS-managed HSM
└── You trust AWS to never export keys


CloudHSM:
Key material in YOUR HSM
├── Physically impossible to export
├── Hardware-enforced
└── You have proof


### 4. Regulatory Compliance

Required for:
- PCI-DSS Level 1 (payment card industry)
- Government/defense contracts
- Financial services regulations
- Healthcare (some HIPAA requirements)
- Data sovereignty requirements

### 5. Audit Trail

You control:
- Who accesses HSM
- When keys are used
- Complete audit logs
- Physical security

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━


## Cost Comparison

### Standard KMS

Cost:
- Key: $1/month
- Requests: $0.03 per 10,000

Example (1M requests/month):
- Key: $1
- Requests: $3
- Total: $4/month


### Custom Key Store (CloudHSM)

Cost:
- CloudHSM: $1.60/hour per HSM = $1,152/month
- Minimum 2 HSMs (HA): $2,304/month
- KMS key: $1/month
- Requests: $0.03 per 10,000

Example (1M requests/month):
- CloudHSM: $2,304
- Key: $1
- Requests: $3
- Total: $2,308/month

576x more expensive!


━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━


## Implementation: EC2 → DynamoDB with CloudHSM Custom Key Store

### Step 1: Create CloudHSM Cluster

bash
# Create CloudHSM cluster
aws cloudhsmv2 create-cluster \
  --hsm-type hsm1.medium \
  --subnet-ids subnet-xxxxx subnet-yyyyy

# Get cluster ID
CLUSTER_ID=$(aws cloudhsmv2 describe-clusters \
  --query 'Clusters[0].ClusterId' \
  --output text)

# Create HSM instances (minimum 2 for HA)
aws cloudhsmv2 create-hsm \
  --cluster-id $CLUSTER_ID \
  --availability-zone us-east-1a

aws cloudhsmv2 create-hsm \
  --cluster-id $CLUSTER_ID \
  --availability-zone us-east-1b

# Wait for HSMs to be active (~10 minutes)
aws cloudhsmv2 describe-clusters --cluster-id $CLUSTER_ID


### Step 2: Initialize CloudHSM Cluster

bash
# Download cluster certificate
aws cloudhsmv2 describe-clusters \
  --cluster-id $CLUSTER_ID \
  --query 'Clusters[0].Certificates.ClusterCertificate' \
  --output text > cluster-cert.crt

# Initialize cluster (first time only)
# This creates the Crypto Officer (CO) user
# Follow CloudHSM initialization guide


### Step 3: Create Custom Key Store

bash
# Create custom key store in KMS
aws kms create-custom-key-store \
  --custom-key-store-name my-hsm-store \
  --cloud-hsm-cluster-id $CLUSTER_ID \
  --key-store-password MySecurePassword123 \
  --trust-anchor-certificate file://cluster-cert.crt

# Get custom key store ID
KEY_STORE_ID=$(aws kms describe-custom-key-stores \
  --custom-key-store-name my-hsm-store \
  --query 'CustomKeyStores[0].CustomKeyStoreId' \
  --output text)

# Connect key store to CloudHSM
aws kms connect-custom-key-store \
  --custom-key-store-id $KEY_STORE_ID


### Step 4: Create KMS Key in Custom Key Store

bash
# Create symmetric key in CloudHSM
aws kms create-key \
  --description "DynamoDB encryption key in CloudHSM" \
  --origin AWS_CLOUDHSM \
  --custom-key-store-id $KEY_STORE_ID \
  --key-usage ENCRYPT_DECRYPT

# Get key ID
KEY_ID=$(aws kms list-keys \
  --query 'Keys[0].KeyId' \
  --output text)

# Create alias
aws kms create-alias \
  --alias-name alias/dynamodb-hsm-key \
  --target-key-id $KEY_ID

# Enable rotation
aws kms enable-key-rotation --key-id $KEY_ID


### Step 5: Create DynamoDB Table with CloudHSM Key

bash
# Create table with CloudHSM-backed KMS key
aws dynamodb create-table \
  --table-name products \
  --attribute-definitions \
    AttributeName=id,AttributeType=S \
  --key-schema \
    AttributeName=id,KeyType=HASH \
  --billing-mode PAY_PER_REQUEST \
  --sse-specification \
    Enabled=true,\
    SSEType=KMS,\
    KMSMasterKeyId=alias/dynamodb-hsm-key


### Step 6: Application Code (Same as Before!)

javascript
const { DynamoDBClient } = require('@aws-sdk/client-dynamodb');
const { DynamoDBDocumentClient, PutCommand, GetCommand } = require('@aws-sdk/lib-dynamodb');

const client = new DynamoDBClient({ region: 'us-east-1' });
const docClient = DynamoDBDocumentClient.from(client);

// Write data (encrypted with CloudHSM key)
async function putItem(product) {
  const params = {
    TableName: 'products',
    Item: {
      id: product.id,
      name: product.name,
      price: product.price,
      createdAt: new Date().toISOString()
    }
  };

  await docClient.send(new PutCommand(params));
  console.log('Item encrypted with CloudHSM key');
}

// Read data (decrypted with CloudHSM key)
async function getItem(productId) {
  const params = {
    TableName: 'products',
    Key: { id: productId }
  };

  const result = await docClient.send(new GetCommand(params));
  console.log('Item decrypted with CloudHSM key');
  return result.Item;
}

// Usage (IDENTICAL to standard KMS)
await putItem({
  id: 'prod-123',
  name: 'Laptop',
  price: 999.99
});

const product = await getItem('prod-123');
console.log(product);

// Application code doesn't change!


━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━


## Workflow Comparison

### Standard KMS Workflow

Write:
1. App → DynamoDB: PutItem
2. DynamoDB → KMS: GenerateDataKey
3. KMS → AWS HSM: Generate key
4. AWS HSM → KMS: Data key (plaintext + encrypted)
5. KMS → DynamoDB: Data key
6. DynamoDB: Encrypt item with data key
7. DynamoDB: Store encrypted item + encrypted data key

Read:
1. App → DynamoDB: GetItem
2. DynamoDB: Retrieve encrypted item + encrypted data key
3. DynamoDB → KMS: Decrypt data key
4. KMS → AWS HSM: Decrypt
5. AWS HSM → KMS: Plaintext data key
6. KMS → DynamoDB: Plaintext data key
7. DynamoDB: Decrypt item
8. DynamoDB → App: Plaintext item


### CloudHSM Custom Key Store Workflow

Write:
1. App → DynamoDB: PutItem
2. DynamoDB → KMS: GenerateDataKey
3. KMS → YOUR CloudHSM: Generate key
4. YOUR CloudHSM → KMS: Data key (plaintext + encrypted)
5. KMS → DynamoDB: Data key
6. DynamoDB: Encrypt item with data key
7. DynamoDB: Store encrypted item + encrypted data key

Read:
1. App → DynamoDB: GetItem
2. DynamoDB: Retrieve encrypted item + encrypted data key
3. DynamoDB → KMS: Decrypt data key
4. KMS → YOUR CloudHSM: Decrypt
5. YOUR CloudHSM → KMS: Plaintext data key
6. KMS → DynamoDB: Plaintext data key
7. DynamoDB: Decrypt item
8. DynamoDB → App: Plaintext item


Difference: Step 3-4 uses YOUR CloudHSM instead of AWS HSM

Application sees: No difference!

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━


## IAM Permissions (Same as Standard KMS)

json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "dynamodb:PutItem",
        "dynamodb:GetItem",
        "dynamodb:UpdateItem",
        "dynamodb:DeleteItem"
      ],
      "Resource": "arn:aws:dynamodb:us-east-1:ACCOUNT:table/products"
    },
    {
      "Effect": "Allow",
      "Action": [
        "kms:Decrypt",
        "kms:Encrypt",
        "kms:GenerateDataKey",
        "kms:DescribeKey"
      ],
      "Resource": "arn:aws:kms:us-east-1:ACCOUNT:key/KEY-ID"
    }
  ]
}


No additional permissions needed for CloudHSM!

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━


## Performance Impact

### Standard KMS

javascript
// Write 1000 items
const startTime = Date.now();

for (let i = 0; i < 1000; i++) {
  await putItem({ id: `prod-${i}`, name: `Product ${i}`, price: i * 10 });
}

const duration = Date.now() - startTime;
console.log(`Time: ${duration}ms`);
// Output: ~2000ms (2ms per item)


### CloudHSM Custom Key Store

javascript
// Write 1000 items
const startTime = Date.now();

for (let i = 0; i < 1000; i++) {
  await putItem({ id: `prod-${i}`, name: `Product ${i}`, price: i * 10 });
}

const duration = Date.now() - startTime;
console.log(`Time: ${duration}ms`);
// Output: ~3000-4000ms (3-4ms per item)

// Slightly slower due to network latency to CloudHSM


Performance impact: 50-100% slower (still acceptable)

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━


## When to Use CloudHSM Custom Key Store

### Use CloudHSM When:

✅ Regulatory compliance requires FIPS 140-2 Level 3
- PCI-DSS Level 1
- Government contracts
- Financial services

✅ Need proof of key control
- Auditors require dedicated HSM
- Data sovereignty requirements

✅ Budget allows ($2,300+/month)
- Enterprise applications
- High-value data

✅ Need single-tenant hardware
- Security policy requires dedicated hardware

### Use Standard KMS When:

✅ Cost-sensitive ($4/month vs $2,300/month)
- Startups
- Small/medium businesses

✅ FIPS 140-2 Level 2 is sufficient
- Most compliance requirements

✅ Trust AWS security
- Standard for 99% of AWS customers

✅ Simpler management
- No HSM cluster to manage

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━


## Comparison Table

| Feature | Standard KMS | CloudHSM Custom Key Store |
|---------|--------------|---------------------------|
| Cost | $4/month | $2,300/month |
| Setup | 5 minutes | 2-4 hours |
| Management | AWS manages | You manage |
| Performance | Fast (2ms) | Slightly slower (3-4ms) |
| Compliance | FIPS 140-2 Level 2 | FIPS 140-2 Level 3 |
| Hardware | Shared (multi-tenant) | Dedicated (single-tenant) |
| Key Control | AWS controls HSM | You control HSM |
| Symmetric Keys | ✅ Yes | ✅ Yes |
| Asymmetric Keys | ✅ Yes | ✅ Yes |
| DynamoDB Support | ✅ Yes | ✅ Yes |
| Application Code | Same | Same |
| Use Case | 99% of customers | High compliance needs |

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━


## Complete Example: Symmetric Key in CloudHSM

javascript
const { DynamoDBClient } = require('@aws-sdk/client-dynamodb');
const { DynamoDBDocumentClient, PutCommand, GetCommand } = require('@aws-sdk/lib-dynamodb');

const client = new DynamoDBClient({ region: 'us-east-1' });
const docClient = DynamoDBDocumentClient.from(client);

async function demonstrateCloudHSM() {
  console.log('=== CloudHSM Custom Key Store Demo ===\n');
  
  // Write data
  console.log('Writing data...');
  await docClient.send(new PutCommand({
    TableName: 'products',
    Item: {
      id: 'prod-123',
      name: 'Laptop',
      price: 999.99,
      creditCard: '4111-1111-1111-1111'  // Sensitive data
    }
  }));
  console.log('✓ Data encrypted with CloudHSM-backed key');
  console.log('✓ Key material never left your HSM');
  console.log('✓ FIPS 140-2 Level 3 compliant\n');
  
  // Read data
  console.log('Reading data...');
  const result = await docClient.send(new GetCommand({
    TableName: 'products',
    Key: { id: 'prod-123' }
  }));
  console.log('✓ Data decrypted with CloudHSM-backed key');
  console.log('✓ Retrieved:', result.Item);
  
  console.log('\n=== Benefits ===');
  console.log('✓ Dedicated hardware (single-tenant)');
  console.log('✓ You control HSM cluster');
  console.log('✓ FIPS 140-2 Level 3');
  console.log('✓ Meets strict compliance requirements');
  console.log('✓ Same application code as standard KMS');
}

demonstrateCloudHSM();


━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━


## Summary

### CloudHSM Custom Key Store:

1. Not about symmetric vs asymmetric - Supports both
2. About WHERE keys are stored - Your HSM vs AWS HSM
3. For strict compliance - FIPS 140-2 Level 3, PCI-DSS Level 1
4. Much more expensive - $2,300/month vs $4/month
5. Same application code - Transparent to application
6. Slightly slower - 50-100% latency increase
7. More management - You manage HSM cluster

### Decision:

Use Standard KMS unless you have specific compliance requirements that mandate FIPS 140-2 Level 3 or dedicated HSM hardware.

99% of customers use Standard KMS.