## Yes, KMS Supports Using Your Own Keys for S3

You have two options to use your own keys with S3:

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━


## Option 1: Customer Managed KMS Key (Recommended)

You create and manage the key in KMS, then use it for S3 encryption.

### Step 1: Create Customer Managed Key

bash
# Create your own KMS key
aws kms create-key \
  --description "My S3 encryption key" \
  --key-usage ENCRYPT_DECRYPT

# Output: KeyId: 1234abcd-12ab-34cd-56ef-1234567890ab

# Create alias for easy reference
aws kms create-alias \
  --alias-name alias/my-s3-key \
  --target-key-id 1234abcd-12ab-34cd-56ef-1234567890ab


### Step 2: Update Key Policy for S3

bash
# Add S3 permissions to key policy
aws kms put-key-policy \
  --key-id alias/my-s3-key \
  --policy-name default \
  --policy '{
    "Version": "2012-10-17",
    "Statement": [
      {
        "Sid": "Enable IAM User Permissions",
        "Effect": "Allow",
        "Principal": {
          "AWS": "arn:aws:iam::ACCOUNT-ID:root"
        },
        "Action": "kms:*",
        "Resource": "*"
      },
      {
        "Sid": "Allow S3 to use the key",
        "Effect": "Allow",
        "Principal": {
          "Service": "s3.amazonaws.com"
        },
        "Action": [
          "kms:Decrypt",
          "kms:GenerateDataKey"
        ],
        "Resource": "*"
      }
    ]
  }'


### Step 3: Enable S3 Bucket Encryption with Your Key

bash
# Enable default encryption on bucket
aws s3api put-bucket-encryption \
  --bucket my-bucket \
  --server-side-encryption-configuration '{
    "Rules": [{
      "ApplyServerSideEncryptionByDefault": {
        "SSEAlgorithm": "aws:kms",
        "KMSMasterKeyID": "alias/my-s3-key"
      },
      "BucketKeyEnabled": true
    }]
  }'


### Step 4: Upload Objects (Automatically Encrypted)

bash
# Upload file - automatically encrypted with your key
aws s3 cp file.txt s3://my-bucket/

# Or specify key explicitly
aws s3 cp file.txt s3://my-bucket/ \
  --server-side-encryption aws:kms \
  --ssekms-key-id alias/my-s3-key


### Application Code (Node.js)

javascript
const { S3Client, PutObjectCommand, GetObjectCommand } = require('@aws-sdk/client-s3');

const s3 = new S3Client({ region: 'us-east-1' });

// Upload with your KMS key
async function uploadFile(fileContent) {
  await s3.send(new PutObjectCommand({
    Bucket: 'my-bucket',
    Key: 'file.txt',
    Body: fileContent,
    ServerSideEncryption: 'aws:kms',
    SSEKMSKeyId: 'alias/my-s3-key'  // Your key
  }));
  
  console.log('File encrypted with your KMS key');
}

// Download (automatically decrypted)
async function downloadFile() {
  const response = await s3.send(new GetObjectCommand({
    Bucket: 'my-bucket',
    Key: 'file.txt'
  }));
  
  // File automatically decrypted by KMS
  const content = await response.Body.transformToString();
  console.log('File decrypted:', content);
}


Benefits:
- ✅ You control the key
- ✅ You can rotate the key
- ✅ You can disable/delete the key
- ✅ Full audit trail in CloudTrail
- ✅ Cross-account access possible
- ✅ Key never leaves AWS (secure)

Cost:
- $1/month per key
- $0.03 per 10,000 requests

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━


## Option 2: Import Your Own Key Material (BYOK)

You generate the key material yourself and import it into KMS.

### Step 1: Create KMS Key Without Key Material

bash
# Create key with external origin
aws kms create-key \
  --description "My imported key for S3" \
  --origin EXTERNAL

# Output: KeyId: 5678efgh-56ef-78gh-90ij-5678901234ef

# Create alias
aws kms create-alias \
  --alias-name alias/my-imported-s3-key \
  --target-key-id 5678efgh-56ef-78gh-90ij-5678901234ef


### Step 2: Get Import Parameters

bash
# Get wrapping key and import token
aws kms get-parameters-for-import \
  --key-id alias/my-imported-s3-key \
  --wrapping-algorithm RSAES_OAEP_SHA_256 \
  --wrapping-key-spec RSA_2048

# Save outputs
# - WrappingKey (public key)
# - ImportToken


### Step 3: Generate Your Own Key Material

bash
# Generate 256-bit key material (on your secure system)
openssl rand -out key-material.bin 32

# This is YOUR key material that you generated


### Step 4: Encrypt Key Material

bash
# Encrypt your key material with AWS wrapping key
openssl pkeyutl -encrypt \
  -in key-material.bin \
  -out encrypted-key-material.bin \
  -inkey wrapping-key.pem \
  -keyform DER \
  -pubin \
  -pkeyopt rsa_padding_mode:oaep \
  -pkeyopt rsa_oaep_md:sha256


### Step 5: Import Key Material to KMS

bash
# Import your key material
aws kms import-key-material \
  --key-id alias/my-imported-s3-key \
  --encrypted-key-material fileb://encrypted-key-material.bin \
  --import-token fileb://import-token.bin \
  --expiration-model KEY_MATERIAL_DOES_NOT_EXPIRE


### Step 6: Use with S3 (Same as Option 1)

bash
# Enable bucket encryption with imported key
aws s3api put-bucket-encryption \
  --bucket my-bucket \
  --server-side-encryption-configuration '{
    "Rules": [{
      "ApplyServerSideEncryptionByDefault": {
        "SSEAlgorithm": "aws:kms",
        "KMSMasterKeyID": "alias/my-imported-s3-key"
      }
    }]
  }'

# Upload files
aws s3 cp file.txt s3://my-bucket/


Benefits:
- ✅ You generate the key material
- ✅ Proof of key origin
- ✅ Can delete key material immediately
- ✅ Meets compliance for key generation

Drawbacks:
- ❌ You must backup key material
- ❌ No automatic rotation
- ❌ More complex management
- ❌ If key material lost, data unrecoverable

Cost:
- $1/month per key
- $0.03 per 10,000 requests

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━


## Comparison

| Feature | Customer Managed Key | Imported Key (BYOK) |
|---------|---------------------|---------------------|
| Key Generation | AWS generates | You generate |
| Key Storage | AWS KMS | AWS KMS (after import) |
| Automatic Rotation | ✅ Yes | ❌ No |
| Complexity | Simple | Complex |
| Backup | AWS handles | You handle |
| Compliance | Most cases | Strict key generation requirements |
| Cost | $1/month | $1/month |
| Recommended | ✅ Yes (90% of cases) | Only if required |

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━


## Complete Example: S3 with Customer Managed Key

javascript
const { S3Client, PutObjectCommand, GetObjectCommand } = require('@aws-sdk/client-s3');
const { KMSClient, CreateKeyCommand, CreateAliasCommand } = require('@aws-sdk/client-kms');

const kms = new KMSClient({ region: 'us-east-1' });
const s3 = new S3Client({ region: 'us-east-1' });

async function setup() {
  // 1. Create your KMS key
  const keyResponse = await kms.send(new CreateKeyCommand({
    Description: 'My S3 encryption key',
    KeyUsage: 'ENCRYPT_DECRYPT'
  }));
  
  const keyId = keyResponse.KeyMetadata.KeyId;
  console.log('Created key:', keyId);
  
  // 2. Create alias
  await kms.send(new CreateAliasCommand({
    AliasName: 'alias/my-s3-key',
    TargetKeyId: keyId
  }));
  
  console.log('Created alias: alias/my-s3-key');
  
  // 3. Upload file with your key
  await s3.send(new PutObjectCommand({
    Bucket: 'my-bucket',
    Key: 'sensitive-data.txt',
    Body: 'This is encrypted with MY key',
    ServerSideEncryption: 'aws:kms',
    SSEKMSKeyId: 'alias/my-s3-key'
  }));
  
  console.log('File uploaded and encrypted with your key');
  
  // 4. Download file (automatically decrypted)
  const response = await s3.send(new GetObjectCommand({
    Bucket: 'my-bucket',
    Key: 'sensitive-data.txt'
  }));
  
  const content = await response.Body.transformToString();
  console.log('File decrypted:', content);
  
  console.log('\n✅ You control the encryption key!');
  console.log('✅ You can rotate, disable, or delete the key');
  console.log('✅ Full audit trail in CloudTrail');
}

setup();


━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━


## IAM Permissions Required

json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "s3:PutObject",
        "s3:GetObject"
      ],
      "Resource": "arn:aws:s3:::my-bucket/*"
    },
    {
      "Effect": "Allow",
      "Action": [
        "kms:Decrypt",
        "kms:Encrypt",
        "kms:GenerateDataKey",
        "kms:DescribeKey"
      ],
      "Resource": "arn:aws:kms:us-east-1:ACCOUNT-ID:key/KEY-ID"
    }
  ]
}


━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━


## Summary

Yes, KMS supports using your own keys for S3 encryption:

1. Customer Managed Key (Recommended) - You create and manage key in KMS
   - Simple, secure, automatic rotation
   - $1/month

2. Import Your Own Key (BYOK) - You generate key material and import
   - Complex, manual rotation, you backup key
   - $1/month

Most people use Option 1 (Customer Managed Key) - it gives you full control while AWS handles the complexity.