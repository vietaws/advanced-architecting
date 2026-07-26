## Complete Workflow: EC2 → DynamoDB with KMS Encryption

### Architecture
EC2 Application → DynamoDB (encrypted at rest) → KMS Key


━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━


## Step 1: Create KMS Key

bash
# Create customer managed key
aws kms create-key \
  --description "DynamoDB encryption key" \
  --key-usage ENCRYPT_DECRYPT

# Output: Key ID: 1234abcd-12ab-34cd-56ef-1234567890ab

# Create alias
aws kms create-alias \
  --alias-name alias/dynamodb-key \
  --target-key-id 1234abcd-12ab-34cd-56ef-1234567890ab

# Enable automatic rotation
aws kms enable-key-rotation \
  --key-id 1234abcd-12ab-34cd-56ef-1234567890ab


━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━


## Step 2: Create DynamoDB Table with KMS Encryption

bash
# Create table with KMS encryption
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
    KMSMasterKeyId=alias/dynamodb-key


━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━


## Step 3: Configure IAM Role for EC2

bash
# Create IAM role for EC2
aws iam create-role \
  --role-name EC2-DynamoDB-Role \
  --assume-role-policy-document '{
    "Version": "2012-10-17",
    "Statement": [{
      "Effect": "Allow",
      "Principal": { "Service": "ec2.amazonaws.com" },
      "Action": "sts:AssumeRole"
    }]
  }'

# Attach policy
aws iam put-role-policy \
  --role-name EC2-DynamoDB-Role \
  --policy-name DynamoDB-KMS-Policy \
  --policy-document '{
    "Version": "2012-10-17",
    "Statement": [
      {
        "Effect": "Allow",
        "Action": [
          "dynamodb:PutItem",
          "dynamodb:GetItem",
          "dynamodb:UpdateItem",
          "dynamodb:DeleteItem",
          "dynamodb:Query",
          "dynamodb:Scan"
        ],
        "Resource": "arn:aws:dynamodb:us-east-1:ACCOUNT-ID:table/products"
      },
      {
        "Effect": "Allow",
        "Action": [
          "kms:Decrypt",
          "kms:Encrypt",
          "kms:GenerateDataKey",
          "kms:DescribeKey"
        ],
        "Resource": "arn:aws:kms:us-east-1:ACCOUNT-ID:key/1234abcd-12ab-34cd-56ef-1234567890ab"
      }
    ]
  }'

# Create instance profile
aws iam create-instance-profile \
  --instance-profile-name EC2-DynamoDB-Profile

# Add role to instance profile
aws iam add-role-to-instance-profile \
  --instance-profile-name EC2-DynamoDB-Profile \
  --role-name EC2-DynamoDB-Role

# Attach to EC2 instance
aws ec2 associate-iam-instance-profile \
  --instance-id i-xxxxx \
  --iam-instance-profile Name=EC2-DynamoDB-Profile


━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━


## Step 4: Application Code (Node.js)

### Install Dependencies

bash
npm install @aws-sdk/client-dynamodb @aws-sdk/lib-dynamodb


### Application Code

javascript
const { DynamoDBClient } = require('@aws-sdk/client-dynamodb');
const { DynamoDBDocumentClient, PutCommand, GetCommand } = require('@aws-sdk/lib-dynamodb');

// Create DynamoDB client
const client = new DynamoDBClient({ region: 'us-east-1' });
const docClient = DynamoDBDocumentClient.from(client);

const TABLE_NAME = 'products';

// Put item (Write operation)
async function putItem(product) {
  const params = {
    TableName: TABLE_NAME,
    Item: {
      id: product.id,
      name: product.name,
      price: product.price,
      description: product.description,
      createdAt: new Date().toISOString()
    }
  };

  try {
    await docClient.send(new PutCommand(params));
    console.log('Item saved successfully');
    return { success: true };
  } catch (error) {
    console.error('Error saving item:', error);
    throw error;
  }
}

// Get item (Read operation)
async function getItem(productId) {
  const params = {
    TableName: TABLE_NAME,
    Key: {
      id: productId
    }
  };

  try {
    const result = await docClient.send(new GetCommand(params));
    
    if (!result.Item) {
      console.log('Item not found');
      return null;
    }
    
    console.log('Item retrieved successfully');
    return result.Item;
  } catch (error) {
    console.error('Error retrieving item:', error);
    throw error;
  }
}

// Example usage
async function main() {
  // Write data
  await putItem({
    id: 'prod-123',
    name: 'Laptop',
    price: 999.99,
    description: 'High-performance laptop'
  });

  // Read data
  const product = await getItem('prod-123');
  console.log('Retrieved product:', product);
}

main();


━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━


## Detailed Workflow

### Write Operation (PutItem)

Step 1: Application calls putItem()
├── Application: Sends plaintext data to DynamoDB
└── Data: { id: 'prod-123', name: 'Laptop', price: 999.99 }

Step 2: DynamoDB receives request
├── DynamoDB: Needs to encrypt data at rest
└── Calls KMS to generate data key

Step 3: KMS generates data key
├── KMS: Generates 256-bit data key
├── Returns: Plaintext data key + Encrypted data key
└── Uses: Current active key version (e.g., key-v1)

Step 4: DynamoDB encrypts data
├── Uses: Plaintext data key to encrypt item
├── Stores: Encrypted item + Encrypted data key
└── Discards: Plaintext data key (security)

Step 5: Data stored on disk
├── Item data: Encrypted with data key
├── Data key: Encrypted with KMS key-v1
└── Metadata: Which KMS key version was used

Application sees: Success response (no encryption details)


Visual:
Application → DynamoDB
              ↓
              Calls KMS: "Generate data key"
              ↓
              KMS returns:
              ├── Plaintext data key: [random 256-bit key]
              └── Encrypted data key: [encrypted with key-v1]
              ↓
              DynamoDB encrypts item with plaintext data key
              ↓
              Stores on disk:
              ├── Encrypted item data
              └── Encrypted data key


### Read Operation (GetItem)

Step 1: Application calls getItem()
├── Application: Requests item by ID
└── Request: { id: 'prod-123' }

Step 2: DynamoDB retrieves encrypted data
├── Reads from disk: Encrypted item + Encrypted data key
└── Metadata shows: Encrypted with key-v1

Step 3: DynamoDB calls KMS to decrypt data key
├── Sends: Encrypted data key to KMS
└── KMS: Uses key-v1 to decrypt data key

Step 4: KMS returns plaintext data key
├── KMS: Decrypts using key-v1 (same version used to encrypt)
└── Returns: Plaintext data key

Step 5: DynamoDB decrypts item
├── Uses: Plaintext data key to decrypt item
├── Returns: Plaintext item to application
└── Discards: Plaintext data key

Application receives: Plaintext data
{ id: 'prod-123', name: 'Laptop', price: 999.99 }


Visual:
Application → DynamoDB
              ↓
              Retrieves from disk:
              ├── Encrypted item
              └── Encrypted data key (encrypted with key-v1)
              ↓
              Calls KMS: "Decrypt this data key"
              ↓
              KMS:
              ├── Sees metadata: "encrypted with key-v1"
              ├── Uses key-v1 to decrypt
              └── Returns plaintext data key
              ↓
              DynamoDB decrypts item with plaintext data key
              ↓
              Returns plaintext to application


━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━


## Key Rotation Impact

### Timeline

Day 1: Initial Setup
KMS Key: key-v1 (active)
Application writes 1000 items
All items encrypted with data keys protected by key-v1


Day 365: Automatic Rotation Occurs
KMS Key:
├── key-v2 (active) - for NEW encryptions
└── key-v1 (archived) - for OLD decryptions

DynamoDB table:
├── 1000 old items (data keys encrypted with key-v1)
└── Ready for new items (will use key-v2)


Day 366: Application Continues
Write new item:
├── DynamoDB calls KMS for data key
├── KMS uses key-v2 (current active version)
└── Item encrypted with data key protected by key-v2

Read old item (from Day 1):
├── DynamoDB retrieves encrypted data key
├── Metadata shows: "encrypted with key-v1"
├── KMS uses key-v1 to decrypt data key
└── Item decrypted successfully

Read new item (from Day 366):
├── DynamoDB retrieves encrypted data key
├── Metadata shows: "encrypted with key-v2"
├── KMS uses key-v2 to decrypt data key
└── Item decrypted successfully


### Impact on Application: ZERO

javascript
// Day 1 (before rotation)
await putItem({ id: 'prod-1', name: 'Item 1' });  // Uses key-v1
await getItem('prod-1');  // Decrypts with key-v1

// Day 365: Rotation happens (automatic, no downtime)

// Day 366 (after rotation)
await putItem({ id: 'prod-2', name: 'Item 2' });  // Uses key-v2
await getItem('prod-1');  // Still decrypts with key-v1 ✓
await getItem('prod-2');  // Decrypts with key-v2 ✓

// NO CODE CHANGES NEEDED!


━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━


## Complete Example with Express API

javascript
const express = require('express');
const { DynamoDBClient } = require('@aws-sdk/client-dynamodb');
const { DynamoDBDocumentClient, PutCommand, GetCommand, ScanCommand } = require('@aws-sdk/lib-dynamodb');

const app = express();
app.use(express.json());

// DynamoDB client
const client = new DynamoDBClient({ region: 'us-east-1' });
const docClient = DynamoDBDocumentClient.from(client);

const TABLE_NAME = 'products';

// Create product
app.post('/products', async (req, res) => {
  const { id, name, price, description } = req.body;
  
  const params = {
    TableName: TABLE_NAME,
    Item: {
      id,
      name,
      price,
      description,
      createdAt: new Date().toISOString()
    }
  };

  try {
    await docClient.send(new PutCommand(params));
    
    console.log('Item encrypted and stored');
    // DynamoDB automatically:
    // 1. Called KMS to generate data key
    // 2. Encrypted item with data key
    // 3. Stored encrypted item + encrypted data key
    
    res.status(201).json({ success: true, id });
  } catch (error) {
    console.error('Error:', error);
    res.status(500).json({ error: error.message });
  }
});

// Get product
app.get('/products/:id', async (req, res) => {
  const params = {
    TableName: TABLE_NAME,
    Key: { id: req.params.id }
  };

  try {
    const result = await docClient.send(new GetCommand(params));
    
    if (!result.Item) {
      return res.status(404).json({ error: 'Product not found' });
    }
    
    console.log('Item decrypted and retrieved');
    // DynamoDB automatically:
    // 1. Retrieved encrypted item + encrypted data key
    // 2. Called KMS to decrypt data key (using correct key version)
    // 3. Decrypted item with plaintext data key
    // 4. Returned plaintext to application
    
    res.json(result.Item);
  } catch (error) {
    console.error('Error:', error);
    res.status(500).json({ error: error.message });
  }
});

// List all products
app.get('/products', async (req, res) => {
  try {
    const result = await docClient.send(new ScanCommand({
      TableName: TABLE_NAME
    }));
    
    // Each item decrypted automatically
    // Items may have been encrypted with different key versions
    // DynamoDB + KMS handle this transparently
    
    res.json(result.Items);
  } catch (error) {
    console.error('Error:', error);
    res.status(500).json({ error: error.message });
  }
});

app.listen(3000, () => {
  console.log('Server running on port 3000');
  console.log('DynamoDB encryption: Transparent to application');
  console.log('Key rotation: Automatic, no impact');
});


━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━


## Testing Key Rotation Impact

javascript
// Test script
async function testKeyRotation() {
  console.log('=== Before Rotation ===');
  
  // Write 100 items
  for (let i = 1; i <= 100; i++) {
    await putItem({
      id: `prod-${i}`,
      name: `Product ${i}`,
      price: i * 10
    });
  }
  console.log('100 items written (encrypted with key-v1)');
  
  // Simulate rotation (in reality, wait 365 days or rotate manually)
  console.log('\n=== Rotation Occurs ===');
  console.log('KMS automatically creates key-v2');
  console.log('key-v1 kept for decryption');
  
  console.log('\n=== After Rotation ===');
  
  // Read old items
  for (let i = 1; i <= 100; i++) {
    const item = await getItem(`prod-${i}`);
    console.log(`Read prod-${i}: ${item.name}`);
    // Decrypts successfully with key-v1
  }
  
  // Write new items
  for (let i = 101; i <= 200; i++) {
    await putItem({
      id: `prod-${i}`,
      name: `Product ${i}`,
      price: i * 10
    });
  }
  console.log('100 new items written (encrypted with key-v2)');
  
  // Read mix of old and new items
  const oldItem = await getItem('prod-50');   // Uses key-v1
  const newItem = await getItem('prod-150');  // Uses key-v2
  
  console.log('Old item:', oldItem);  // Works!
  console.log('New item:', newItem);  // Works!
  
  console.log('\n=== Result ===');
  console.log('✓ All operations successful');
  console.log('✓ No code changes needed');
  console.log('✓ Transparent key rotation');
}


━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━


## Monitoring

bash
# Monitor KMS usage
aws cloudwatch get-metric-statistics \
  --namespace AWS/KMS \
  --metric-name NumberOfDecryptCalls \
  --dimensions Name=KeyId,Value=1234abcd-12ab-34cd-56ef-1234567890ab \
  --start-time 2026-02-08T00:00:00Z \
  --end-time 2026-02-08T19:00:00Z \
  --period 3600 \
  --statistics Sum

# Check key rotation status
aws kms get-key-rotation-status \
  --key-id 1234abcd-12ab-34cd-56ef-1234567890ab

# View CloudTrail logs
aws cloudtrail lookup-events \
  --lookup-attributes AttributeKey=ResourceName,AttributeValue=1234abcd-12ab-34cd-56ef-1234567890ab \
  --max-results 10


━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━


## Summary

### Workflow Impact

| Operation | Before Rotation | After Rotation | Code Changes |
|-----------|----------------|----------------|--------------|
| Write | Uses key-v1 | Uses key-v2 | None |
| Read old data | Uses key-v1 | Uses key-v1 | None |
| Read new data | Uses key-v1 | Uses key-v2 | None |
| Application | Works | Works | None |

### Key Points

1. Encryption is transparent - Application never sees encrypted data
2. Key rotation is automatic - No application changes needed
3. Old data readable forever - KMS keeps all key versions
4. No performance impact - Rotation happens in background
5. Zero downtime - Seamless transition

Your application code never changes, regardless of key rotation!