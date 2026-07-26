## KMS Permissions: Symmetric vs Asymmetric Keys

### Key Difference

Symmetric keys support ALL three operations:
- ✅ kms:GenerateDataKey
- ✅ kms:Encrypt
- ✅ kms:Decrypt

Asymmetric keys support LIMITED operations:
- ❌ kms:GenerateDataKey (NOT supported)
- ✅ kms:Encrypt (with public key)
- ✅ kms:Decrypt (with private key)

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━


## Symmetric Key Examples

### 1. GenerateDataKey (Envelope Encryption)

javascript
const { KMSClient, GenerateDataKeyCommand, DecryptCommand } = require('@aws-sdk/client-kms');
const crypto = require('crypto');

const kms = new KMSClient({ region: 'us-east-1' });

// Encrypt large file with symmetric key
async function encryptLargeFile(fileData) {
  // 1. Generate data key
  const dataKeyResponse = await kms.send(new GenerateDataKeyCommand({
    KeyId: 'alias/symmetric-key',
    KeySpec: 'AES_256'
  }));
  
  // 2. Encrypt file with plaintext data key (locally)
  const iv = crypto.randomBytes(16);
  const cipher = crypto.createCipheriv('aes-256-gcm', dataKeyResponse.Plaintext, iv);
  const encrypted = Buffer.concat([
    cipher.update(fileData),
    cipher.final()
  ]);
  
  // 3. Return encrypted file + encrypted data key
  return {
    encryptedData: encrypted,
    encryptedDataKey: dataKeyResponse.CiphertextBlob,  // Store this
    iv: iv,
    authTag: cipher.getAuthTag()
  };
}

// Decrypt large file
async function decryptLargeFile(encryptedData, encryptedDataKey, iv, authTag) {
  // 1. Decrypt data key with KMS
  const dataKeyResponse = await kms.send(new DecryptCommand({
    CiphertextBlob: encryptedDataKey
  }));
  
  // 2. Decrypt file with plaintext data key (locally)
  const decipher = crypto.createDecipheriv('aes-256-gcm', dataKeyResponse.Plaintext, iv);
  decipher.setAuthTag(authTag);
  const decrypted = Buffer.concat([
    decipher.update(encryptedData),
    decipher.final()
  ]);
  
  return decrypted;
}

// Usage
const fileData = Buffer.from('Large file content...'.repeat(1000));  // Large file
const encrypted = await encryptLargeFile(fileData);
const decrypted = await decryptLargeFile(
  encrypted.encryptedData,
  encrypted.encryptedDataKey,
  encrypted.iv,
  encrypted.authTag
);


Permissions needed:
json
{
  "Effect": "Allow",
  "Action": [
    "kms:GenerateDataKey",
    "kms:Decrypt"
  ],
  "Resource": "arn:aws:kms:us-east-1:ACCOUNT-ID:key/SYMMETRIC-KEY-ID"
}


━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━


### 2. Encrypt/Decrypt (Direct Encryption)

javascript
const { EncryptCommand, DecryptCommand } = require('@aws-sdk/client-kms');

// Encrypt small data directly with symmetric key
async function encryptSmallData(data) {
  const response = await kms.send(new EncryptCommand({
    KeyId: 'alias/symmetric-key',
    Plaintext: Buffer.from(data)  // Max 4KB
  }));
  
  return response.CiphertextBlob;
}

// Decrypt
async function decryptSmallData(ciphertext) {
  const response = await kms.send(new DecryptCommand({
    CiphertextBlob: ciphertext
  }));
  
  return response.Plaintext.toString();
}

// Usage
const encrypted = await encryptSmallData('password123');
const decrypted = await decryptSmallData(encrypted);


Permissions needed:
json
{
  "Effect": "Allow",
  "Action": [
    "kms:Encrypt",
    "kms:Decrypt"
  ],
  "Resource": "arn:aws:kms:us-east-1:ACCOUNT-ID:key/SYMMETRIC-KEY-ID"
}


━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━


## Asymmetric Key Examples

### 1. GenerateDataKey (NOT SUPPORTED)

javascript
// ❌ This DOES NOT WORK with asymmetric keys
await kms.send(new GenerateDataKeyCommand({
  KeyId: 'alias/asymmetric-key',  // Asymmetric key
  KeySpec: 'AES_256'
}));

// Error: InvalidKeyUsageException
// GenerateDataKey is not supported for asymmetric keys


Workaround: Manual envelope encryption
javascript
const { GetPublicKeyCommand, DecryptCommand } = require('@aws-sdk/client-kms');
const crypto = require('crypto');

// Encrypt large file with asymmetric key (manual envelope encryption)
async function encryptLargeFileAsymmetric(fileData) {
  // 1. Generate data key locally (not from KMS)
  const dataKey = crypto.randomBytes(32);  // 256-bit key
  
  // 2. Encrypt file with data key
  const iv = crypto.randomBytes(16);
  const cipher = crypto.createCipheriv('aes-256-gcm', dataKey, iv);
  const encrypted = Buffer.concat([
    cipher.update(fileData),
    cipher.final()
  ]);
  
  // 3. Encrypt data key with KMS asymmetric public key
  const encryptedDataKey = await kms.send(new EncryptCommand({
    KeyId: 'alias/asymmetric-key',
    Plaintext: dataKey,
    EncryptionAlgorithm: 'RSAES_OAEP_SHA_256'
  }));
  
  return {
    encryptedData: encrypted,
    encryptedDataKey: encryptedDataKey.CiphertextBlob,
    iv: iv,
    authTag: cipher.getAuthTag()
  };
}

// Decrypt
async function decryptLargeFileAsymmetric(encryptedData, encryptedDataKey, iv, authTag) {
  // 1. Decrypt data key with KMS asymmetric private key
  const dataKeyResponse = await kms.send(new DecryptCommand({
    KeyId: 'alias/asymmetric-key',
    CiphertextBlob: encryptedDataKey,
    EncryptionAlgorithm: 'RSAES_OAEP_SHA_256'
  }));
  
  // 2. Decrypt file with data key
  const decipher = crypto.createDecipheriv('aes-256-gcm', dataKeyResponse.Plaintext, iv);
  decipher.setAuthTag(authTag);
  const decrypted = Buffer.concat([
    decipher.update(encryptedData),
    decipher.final()
  ]);
  
  return decrypted;
}


Permissions needed:
json
{
  "Effect": "Allow",
  "Action": [
    "kms:Encrypt",
    "kms:Decrypt",
    "kms:GetPublicKey"
  ],
  "Resource": "arn:aws:kms:us-east-1:ACCOUNT-ID:key/ASYMMETRIC-KEY-ID"
}


━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━


### 2. Encrypt/Decrypt (Direct Encryption)

javascript
const { EncryptCommand, DecryptCommand } = require('@aws-sdk/client-kms');

// Encrypt with asymmetric key
async function encryptAsymmetric(data) {
  const response = await kms.send(new EncryptCommand({
    KeyId: 'alias/asymmetric-key',
    Plaintext: Buffer.from(data),  // Max 4KB
    EncryptionAlgorithm: 'RSAES_OAEP_SHA_256'  // Required for asymmetric
  }));
  
  return response.CiphertextBlob;
}

// Decrypt with asymmetric key
async function decryptAsymmetric(ciphertext) {
  const response = await kms.send(new DecryptCommand({
    KeyId: 'alias/asymmetric-key',
    CiphertextBlob: ciphertext,
    EncryptionAlgorithm: 'RSAES_OAEP_SHA_256'  // Required for asymmetric
  }));
  
  return response.Plaintext.toString();
}

// Usage
const encrypted = await encryptAsymmetric('secret data');
const decrypted = await decryptAsymmetric(encrypted);


Permissions needed:
json
{
  "Effect": "Allow",
  "Action": [
    "kms:Encrypt",
    "kms:Decrypt"
  ],
  "Resource": "arn:aws:kms:us-east-1:ACCOUNT-ID:key/ASYMMETRIC-KEY-ID"
}


━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━


### 3. External Encryption (Public Key Export)

javascript
const { GetPublicKeyCommand } = require('@aws-sdk/client-kms');
const crypto = require('crypto');

// Get public key (can be done outside AWS)
async function getPublicKey() {
  const response = await kms.send(new GetPublicKeyCommand({
    KeyId: 'alias/asymmetric-key'
  }));
  
  return response.PublicKey;
}

// Encrypt outside AWS (e.g., mobile app)
function encryptWithPublicKey(publicKey, data) {
  return crypto.publicEncrypt(
    {
      key: publicKey,
      padding: crypto.constants.RSA_PKCS1_OAEP_PADDING,
      oaepHash: 'sha256'
    },
    Buffer.from(data)
  );
}

// Decrypt in AWS
async function decryptInAWS(ciphertext) {
  const response = await kms.send(new DecryptCommand({
    KeyId: 'alias/asymmetric-key',
    CiphertextBlob: ciphertext,
    EncryptionAlgorithm: 'RSAES_OAEP_SHA_256'
  }));
  
  return response.Plaintext.toString();
}

// Usage
const publicKey = await getPublicKey();
// Mobile app encrypts locally (offline)
const encrypted = encryptWithPublicKey(publicKey, 'sensitive data');
// Server decrypts with KMS
const decrypted = await decryptInAWS(encrypted);


Permissions needed:
json
{
  "Effect": "Allow",
  "Action": [
    "kms:GetPublicKey",  // To download public key
    "kms:Decrypt"        // To decrypt with private key
  ],
  "Resource": "arn:aws:kms:us-east-1:ACCOUNT-ID:key/ASYMMETRIC-KEY-ID"
}


━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━


## Workflow Comparison

### Symmetric Key Workflow (S3 Example)

Upload:
1. S3 → KMS: GenerateDataKey (symmetric key)
2. KMS → S3: Plaintext key + Encrypted key
3. S3: Encrypt file with plaintext key (AES-256)
4. S3: Store encrypted file + encrypted key

Download:
1. S3: Retrieve encrypted file + encrypted key
2. S3 → KMS: Decrypt(encrypted key)
3. KMS → S3: Plaintext key
4. S3: Decrypt file with plaintext key
5. S3 → User: Decrypted file

Permissions: kms:GenerateDataKey, kms:Decrypt


### Asymmetric Key Workflow (Manual)

Upload:
1. App: Generate data key locally (crypto.randomBytes)
2. App: Encrypt file with data key (AES-256)
3. App → KMS: Encrypt(data key) with asymmetric key
4. KMS → App: Encrypted data key
5. App: Store encrypted file + encrypted data key

Download:
1. App: Retrieve encrypted file + encrypted data key
2. App → KMS: Decrypt(encrypted data key) with asymmetric key
3. KMS → App: Plaintext data key
4. App: Decrypt file with plaintext data key
5. App → User: Decrypted file

Permissions: kms:Encrypt, kms:Decrypt


━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━


## AWS Service Support

### Services Supporting Symmetric Keys ✅

| Service | Symmetric Support | Asymmetric Support |
|---------|-------------------|-------------------|
| S3 | ✅ Yes | ❌ No |
| EBS | ✅ Yes | ❌ No |
| RDS | ✅ Yes | ❌ No |
| DynamoDB | ✅ Yes | ❌ No |
| Lambda | ✅ Yes | ❌ No |
| Secrets Manager | ✅ Yes | ❌ No |
| Systems Manager | ✅ Yes | ❌ No |
| CloudWatch Logs | ✅ Yes | ❌ No |
| SNS | ✅ Yes | ❌ No |
| SQS | ✅ Yes | ❌ No |
| EFS | ✅ Yes | ❌ No |
| Kinesis | ✅ Yes | ❌ No |
| Redshift | ✅ Yes | ❌ No |
| Aurora | ✅ Yes | ❌ No |

Summary: ALL AWS services only support symmetric keys for encryption at rest.

### Asymmetric Keys Use Cases

Asymmetric keys are for custom applications, NOT AWS services:
- ✅ Digital signatures
- ✅ Client-side encryption (mobile apps)
- ✅ External party encryption
- ✅ JWT signing
- ✅ Code signing
- ❌ S3/EBS/RDS/DynamoDB encryption

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━


## Complete Comparison

### Symmetric Key

javascript
// Create symmetric key
aws kms create-key \
  --key-spec SYMMETRIC_DEFAULT \
  --key-usage ENCRYPT_DECRYPT

// Supported operations
✅ kms:GenerateDataKey
✅ kms:Encrypt
✅ kms:Decrypt
✅ kms:ReEncrypt

// AWS service support
✅ S3, EBS, RDS, DynamoDB, etc.

// Use cases
✅ Data at rest encryption
✅ High throughput
✅ Large files
✅ AWS service integration


### Asymmetric Key

javascript
// Create asymmetric key
aws kms create-key \
  --key-spec RSA_2048 \
  --key-usage ENCRYPT_DECRYPT

// Supported operations
❌ kms:GenerateDataKey (NOT supported)
✅ kms:Encrypt (with public key)
✅ kms:Decrypt (with private key)
✅ kms:GetPublicKey (export public key)

// AWS service support
❌ S3, EBS, RDS, DynamoDB, etc. (NOT supported)

// Use cases
✅ Digital signatures
✅ External encryption
✅ Client-side encryption
✅ JWT signing


━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━


## Summary Table

| Operation | Symmetric Key | Asymmetric Key | AWS Services |
|-----------|---------------|----------------|--------------|
| GenerateDataKey | ✅ Yes | ❌ No | S3, EBS, RDS use this |
| Encrypt | ✅ Yes | ✅ Yes | Direct encryption |
| Decrypt | ✅ Yes | ✅ Yes | Decryption |
| GetPublicKey | ❌ No | ✅ Yes | Export public key |
| AWS Service Support | ✅ All services | ❌ None | - |
| Speed | Fast (1-2ms) | Slow (10-50ms) | - |
| Data Size | Unlimited* | 4KB max | - |
| Cost | $0.03/10K | $0.15/10K | - |

Key Takeaway:
- **Symmetric keys** = For AWS services (S3, RDS, DynamoDB, etc.)
- **Asymmetric keys** = For custom applications (signatures, external encryption)
- **AWS services ONLY support symmetric keys**