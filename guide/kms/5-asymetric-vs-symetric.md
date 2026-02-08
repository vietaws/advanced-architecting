## KMS Symmetric vs Asymmetric Keys

### Quick Comparison

| Feature | Symmetric | Asymmetric |
|---------|-----------|------------|
| Keys | 1 key (encrypt & decrypt) | 2 keys (public & private) |
| Algorithm | AES-256 | RSA or ECC |
| Speed | Fast (~1ms) | Slow (~10-50ms) |
| Data Size | Unlimited* | 4KB max |
| Cost | $0.03 per 10K requests | $0.15 per 10K requests |
| Key Export | Cannot export | Can export public key |
| Use Outside AWS | No | Yes (public key) |
| Digital Signatures | No | Yes |
| AWS Service Integration | Excellent | Limited |

With envelope encryption

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━


## 1. Key Structure

### Symmetric Key

Single key for both operations:
Key: [256-bit secret key]
├── Encrypts data
└── Decrypts data

Same key = Must keep secret


Visual:
Plaintext → [Symmetric Key] → Ciphertext
Ciphertext → [Same Key] → Plaintext


Example:
bash
# Create symmetric key
aws kms create-key \
  --description "Symmetric key" \
  --key-usage ENCRYPT_DECRYPT \
  --key-spec SYMMETRIC_DEFAULT

# Key never leaves AWS
# Cannot export or view the key material


### Asymmetric Key

Two keys (key pair):
Public Key: [Can be shared]
├── Encrypts data
└── Verifies signatures

Private Key: [Must keep secret]
├── Decrypts data
└── Creates signatures


Visual:
Plaintext → [Public Key] → Ciphertext
Ciphertext → [Private Key] → Plaintext


Example:
bash
# Create asymmetric key
aws kms create-key \
  --description "Asymmetric key" \
  --key-usage ENCRYPT_DECRYPT \
  --key-spec RSA_2048

# Get public key (can export)
aws kms get-public-key \
  --key-id KEY-ID \
  --output text \
  --query PublicKey | base64 -d > public_key.der

# Private key never leaves AWS


━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━


## 2. Encryption/Decryption

### Symmetric Key

javascript
const { KMSClient, EncryptCommand, DecryptCommand } = require('@aws-sdk/client-kms');

const kms = new KMSClient({ region: 'us-east-1' });

// Encrypt
async function encrypt(plaintext) {
  const command = new EncryptCommand({
    KeyId: 'alias/symmetric-key',
    Plaintext: Buffer.from(plaintext)
  });
  
  const response = await kms.send(command);
  return response.CiphertextBlob;
}

// Decrypt (same key)
async function decrypt(ciphertext) {
  const command = new DecryptCommand({
    CiphertextBlob: ciphertext
    // No KeyId needed - embedded in ciphertext
  });
  
  const response = await kms.send(command);
  return response.Plaintext.toString();
}

// Usage
const encrypted = await encrypt('secret data');
const decrypted = await decrypt(encrypted);

// Speed: ~1-2ms per operation


### Asymmetric Key

javascript
const { KMSClient, EncryptCommand, DecryptCommand, GetPublicKeyCommand } = require('@aws-sdk/client-kms');

const kms = new KMSClient({ region: 'us-east-1' });

// Get public key (can do this outside AWS)
async function getPublicKey() {
  const command = new GetPublicKeyCommand({
    KeyId: 'alias/asymmetric-key'
  });
  
  const response = await kms.send(command);
  return response.PublicKey;
}

// Encrypt with public key (can be done outside AWS)
async function encrypt(plaintext) {
  const command = new EncryptCommand({
    KeyId: 'alias/asymmetric-key',
    Plaintext: Buffer.from(plaintext),
    EncryptionAlgorithm: 'RSAES_OAEP_SHA_256'
  });
  
  const response = await kms.send(command);
  return response.CiphertextBlob;
}

// Decrypt with private key (must use AWS KMS)
async function decrypt(ciphertext) {
  const command = new DecryptCommand({
    KeyId: 'alias/asymmetric-key',
    CiphertextBlob: ciphertext,
    EncryptionAlgorithm: 'RSAES_OAEP_SHA_256'
  });
  
  const response = await kms.send(command);
  return response.Plaintext.toString();
}

// Usage
const encrypted = await encrypt('secret data');  // Max 4KB
const decrypted = await decrypt(encrypted);

// Speed: ~10-50ms per operation


━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━


## 3. Data Size Limits

### Symmetric Key (Unlimited with Envelope Encryption)

javascript
// Direct encryption: 4KB limit
await kms.send(new EncryptCommand({
  KeyId: 'alias/symmetric-key',
  Plaintext: Buffer.from('x'.repeat(4096))  // 4KB max
}));

// Envelope encryption: Unlimited
const { GenerateDataKeyCommand } = require('@aws-sdk/client-kms');
const crypto = require('crypto');

async function encryptLargeFile(fileData) {
  // Generate data key
  const dataKeyResponse = await kms.send(new GenerateDataKeyCommand({
    KeyId: 'alias/symmetric-key',
    KeySpec: 'AES_256'
  }));
  
  // Encrypt file with data key (any size)
  const iv = crypto.randomBytes(16);
  const cipher = crypto.createCipheriv('aes-256-gcm', dataKeyResponse.Plaintext, iv);
  const encrypted = Buffer.concat([
    cipher.update(fileData),  // Can be GB in size
    cipher.final()
  ]);
  
  return {
    encryptedData: encrypted,
    encryptedDataKey: dataKeyResponse.CiphertextBlob,
    iv: iv,
    authTag: cipher.getAuthTag()
  };
}

// Encrypt 1GB file
const largeFile = Buffer.alloc(1024 * 1024 * 1024);  // 1GB
const result = await encryptLargeFile(largeFile);  // ✅ Works


### Asymmetric Key (4KB Maximum)

javascript
// Maximum 4KB
await kms.send(new EncryptCommand({
  KeyId: 'alias/asymmetric-key',
  Plaintext: Buffer.from('x'.repeat(4096)),  // 4KB max
  EncryptionAlgorithm: 'RSAES_OAEP_SHA_256'
}));
// ✅ Works

// More than 4KB
await kms.send(new EncryptCommand({
  KeyId: 'alias/asymmetric-key',
  Plaintext: Buffer.from('x'.repeat(5000)),  // 5KB
  EncryptionAlgorithm: 'RSAES_OAEP_SHA_256'
}));
// ❌ Error: Plaintext too large


━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━


## 4. Use Cases

### Symmetric Key Use Cases

1. AWS Service Encryption (S3, EBS, RDS, DynamoDB)
bash
# S3 encryption
aws s3api put-bucket-encryption \
  --bucket my-bucket \
  --server-side-encryption-configuration '{
    "Rules": [{
      "ApplyServerSideEncryptionByDefault": {
        "SSEAlgorithm": "aws:kms",
        "KMSMasterKeyID": "alias/symmetric-key"
      }
    }]
  }'

# DynamoDB encryption
aws dynamodb create-table \
  --table-name products \
  --sse-specification \
    Enabled=true,\
    SSEType=KMS,\
    KMSMasterKeyId=alias/symmetric-key


2. Application Data Encryption
javascript
// Encrypt sensitive data
async function encryptUserData(userData) {
  const encrypted = await kms.send(new EncryptCommand({
    KeyId: 'alias/symmetric-key',
    Plaintext: Buffer.from(JSON.stringify(userData))
  }));
  
  return encrypted.CiphertextBlob;
}


3. Database Field Encryption
javascript
// Encrypt credit card number
const encryptedCC = await encrypt(creditCardNumber);
await db.query('INSERT INTO payments (user_id, cc_encrypted) VALUES (?, ?)', 
  [userId, encryptedCC]);


### Asymmetric Key Use Cases

1. Digital Signatures
javascript
const { SignCommand, VerifyCommand } = require('@aws-sdk/client-kms');

// Sign data (private key)
async function signData(data) {
  const command = new SignCommand({
    KeyId: 'alias/asymmetric-key',
    Message: Buffer.from(data),
    SigningAlgorithm: 'RSASSA_PSS_SHA_256'
  });
  
  const response = await kms.send(command);
  return response.Signature;
}

// Verify signature (public key - can be done outside AWS)
async function verifySignature(data, signature) {
  const command = new VerifyCommand({
    KeyId: 'alias/asymmetric-key',
    Message: Buffer.from(data),
    Signature: signature,
    SigningAlgorithm: 'RSASSA_PSS_SHA_256'
  });
  
  const response = await kms.send(command);
  return response.SignatureValid;
}

// Usage: Sign software release
const releaseData = fs.readFileSync('app-v1.0.0.zip');
const signature = await signData(releaseData);
// Distribute signature with release for verification


2. External Party Encryption
javascript
// Mobile app encrypts data before sending to AWS
// 1. Download public key once
const publicKey = await kms.send(new GetPublicKeyCommand({
  KeyId: 'alias/asymmetric-key'
}));

// 2. Save public key in mobile app
fs.writeFileSync('public_key.pem', publicKey.PublicKey);

// 3. Mobile app encrypts locally (offline)
const crypto = require('crypto');
const encrypted = crypto.publicEncrypt(
  {
    key: publicKey.PublicKey,
    padding: crypto.constants.RSA_PKCS1_OAEP_PADDING
  },
  Buffer.from('sensitive data')
);

// 4. Send encrypted data to server
// 5. Server decrypts with KMS private key
const decrypted = await kms.send(new DecryptCommand({
  KeyId: 'alias/asymmetric-key',
  CiphertextBlob: encrypted,
  EncryptionAlgorithm: 'RSAES_OAEP_SHA_256'
}));


3. JWT Signing
javascript
const jwt = require('jsonwebtoken');

// Sign JWT with KMS
async function createJWT(payload) {
  const token = jwt.sign(payload, 'placeholder');
  const signature = await signData(token);
  
  return `${token}.${signature.toString('base64')}`;
}

// Verify JWT
async function verifyJWT(token) {
  const [payload, signature] = token.split('.');
  return await verifySignature(payload, Buffer.from(signature, 'base64'));
}


━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━


## 5. Performance Comparison

### Benchmark Test

javascript
// Symmetric key performance
async function testSymmetric() {
  const startTime = Date.now();
  
  for (let i = 0; i < 1000; i++) {
    await kms.send(new EncryptCommand({
      KeyId: 'alias/symmetric-key',
      Plaintext: Buffer.from('test data')
    }));
  }
  
  const duration = Date.now() - startTime;
  console.log(`Symmetric: ${duration}ms for 1000 operations`);
  console.log(`Average: ${duration / 1000}ms per operation`);
  // Output: ~1000ms total, ~1ms per operation
}

// Asymmetric key performance
async function testAsymmetric() {
  const startTime = Date.now();
  
  for (let i = 0; i < 1000; i++) {
    await kms.send(new EncryptCommand({
      KeyId: 'alias/asymmetric-key',
      Plaintext: Buffer.from('test data'),
      EncryptionAlgorithm: 'RSAES_OAEP_SHA_256'
    }));
  }
  
  const duration = Date.now() - startTime;
  console.log(`Asymmetric: ${duration}ms for 1000 operations`);
  console.log(`Average: ${duration / 1000}ms per operation`);
  // Output: ~20000ms total, ~20ms per operation
}

// Results:
// Symmetric: 20x faster


━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━


## 6. Cost Comparison

### Symmetric Key

Monthly key cost: $1
API requests: $0.03 per 10,000 requests

Example:
- 1 million encrypt operations
- 1 million decrypt operations
- Total: 2 million requests

Cost:
- Key: $1
- Requests: (2,000,000 / 10,000) × $0.03 = $6
- Total: $7/month


### Asymmetric Key

Monthly key cost: $1
API requests: $0.15 per 10,000 requests (5x more expensive)

Example:
- 1 million encrypt operations
- 1 million decrypt operations
- Total: 2 million requests

Cost:
- Key: $1
- Requests: (2,000,000 / 10,000) × $0.15 = $30
- Total: $31/month

4.4x more expensive than symmetric!


━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━


## 7. Key Export

### Symmetric Key

bash
# Cannot export symmetric key
aws kms get-public-key --key-id SYMMETRIC-KEY-ID
# Error: InvalidKeyUsageException
# Symmetric keys cannot be exported

# Key material always stays in AWS


### Asymmetric Key

bash
# Can export public key
aws kms get-public-key \
  --key-id ASYMMETRIC-KEY-ID \
  --output text \
  --query PublicKey | base64 -d > public_key.der

# Convert to PEM format
openssl rsa -pubin -inform DER -in public_key.der -outform PEM -out public_key.pem

# Use public key outside AWS
openssl rsautl -encrypt \
  -pubin -inkey public_key.pem \
  -in plaintext.txt \
  -out encrypted.bin

# Private key never leaves AWS


━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━


## 8. AWS Service Integration

### Symmetric Key (Excellent Integration)

bash
# Supported by most AWS services
- S3 ✅
- EBS ✅
- RDS ✅
- DynamoDB ✅
- Lambda environment variables ✅
- Secrets Manager ✅
- Systems Manager Parameter Store ✅
- CloudWatch Logs ✅
- SNS ✅
- SQS ✅


### Asymmetric Key (Limited Integration)

bash
# Limited AWS service support
- S3 ❌
- EBS ❌
- RDS ❌
- DynamoDB ❌
- Lambda environment variables ❌
- Secrets Manager ❌
- Systems Manager Parameter Store ❌
- CloudWatch Logs ❌
- SNS ❌
- SQS ❌

# Mainly for custom applications
- Digital signatures ✅
- Client-side encryption ✅
- JWT signing ✅


━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━


## Decision Tree

Do you need to encrypt data at rest in AWS services?
├─ Yes → Symmetric Key
└─ No → Continue

Do you need digital signatures?
├─ Yes → Asymmetric Key
└─ No → Continue

Do you need to encrypt outside AWS?
├─ Yes → Asymmetric Key
└─ No → Continue

Do you need high throughput (>1000 ops/sec)?
├─ Yes → Symmetric Key
└─ No → Continue

Do you need to encrypt large files (>4KB)?
├─ Yes → Symmetric Key
└─ No → Either works

Default choice: Symmetric Key (90% of use cases)


━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━


## Summary

| Use Case | Key Type |
|----------|----------|
| S3/EBS/RDS/DynamoDB encryption | Symmetric |
| Application data encryption | Symmetric |
| High throughput | Symmetric |
| Large files | Symmetric |
| Low cost | Symmetric |
| Digital signatures | Asymmetric |
| External party encryption | Asymmetric |
| JWT signing | Asymmetric |
| Code signing | Asymmetric |
| Public key distribution | Asymmetric |

Most common choice: Symmetric (90% of use cases)

Asymmetric keys are for specialized use cases like digital signatures and external encryption.