## KMS Permissions: GenerateDataKey vs Encrypt vs Decrypt

### Quick Answer for S3 Use Case

For EC2 uploading/downloading to S3 with KMS encryption, you need:
- kms:GenerateDataKey - For uploads (S3 encrypts data)
- kms:Decrypt - For downloads (S3 decrypts data)
- **NOT** kms:Encrypt - S3 doesn't use this for file encryption

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━


## Understanding Each Permission

### 1. kms:GenerateDataKey

What it does:
- Generates a new data encryption key (DEK)
- Returns BOTH plaintext and encrypted versions
- Used for envelope encryption of large data

When S3 uses it:
- When uploading/writing objects to S3
- S3 requests a data key from KMS
- S3 encrypts the file with plaintext data key
- S3 stores encrypted file + encrypted data key

Example:
javascript
const { GenerateDataKeyCommand } = require('@aws-sdk/client-kms');

// What S3 does internally when you upload
const response = await kms.send(new GenerateDataKeyCommand({
  KeyId: 'alias/my-s3-key',
  KeySpec: 'AES_256'
}));

// Returns:
// - Plaintext: [256-bit key] → Used to encrypt 1MB file
// - CiphertextBlob: [encrypted key] → Stored with file metadata


Data flow:
Upload 1MB file:
1. S3 calls KMS: GenerateDataKey
2. KMS returns: Plaintext key + Encrypted key
3. S3 encrypts 1MB file with plaintext key (locally)
4. S3 stores: Encrypted file + Encrypted key
5. S3 discards plaintext key


━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━


### 2. kms:Decrypt

What it does:
- Decrypts an encrypted data key
- Returns plaintext version of the key
- Used to decrypt data that was encrypted with a data key

When S3 uses it:
- When downloading/reading objects from S3
- S3 retrieves encrypted data key from object metadata
- S3 sends encrypted data key to KMS
- KMS decrypts and returns plaintext data key
- S3 uses plaintext key to decrypt the file

Example:
javascript
const { DecryptCommand } = require('@aws-sdk/client-kms');

// What S3 does internally when you download
const response = await kms.send(new DecryptCommand({
  CiphertextBlob: encryptedDataKey  // From object metadata
}));

// Returns:
// - Plaintext: [256-bit key] → Used to decrypt 1MB file


Data flow:
Download 1MB file:
1. S3 retrieves: Encrypted file + Encrypted data key
2. S3 calls KMS: Decrypt(encrypted data key)
3. KMS returns: Plaintext data key
4. S3 decrypts 1MB file with plaintext key (locally)
5. S3 returns decrypted file to application
6. S3 discards plaintext key


━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━


### 3. kms:Encrypt

What it does:
- Encrypts small data (up to 4KB) directly with KMS key
- Returns encrypted ciphertext
- **NOT used by S3** for file encryption

When to use:
- Encrypting small secrets (passwords, API keys)
- Encrypting database fields
- Direct encryption without envelope encryption

Example:
javascript
const { EncryptCommand } = require('@aws-sdk/client-kms');

// Direct encryption (NOT what S3 does)
const response = await kms.send(new EncryptCommand({
  KeyId: 'alias/my-key',
  Plaintext: Buffer.from('small secret data')  // Max 4KB
}));

// Returns:
// - CiphertextBlob: [encrypted data]


Why S3 doesn't use this:
- Limited to 4KB
- Slower than envelope encryption
- More expensive (KMS API call per file)

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━


## S3 Encryption Workflow

### Upload 1MB File to S3

javascript
const { S3Client, PutObjectCommand } = require('@aws-sdk/client-s3');

const s3 = new S3Client({ region: 'us-east-1' });

// Upload file
await s3.send(new PutObjectCommand({
  Bucket: 'my-bucket',
  Key: 'file.dat',
  Body: fileContent,  // 1MB
  ServerSideEncryption: 'aws:kms',
  SSEKMSKeyId: 'alias/my-s3-key'
}));


Behind the scenes:
1. S3 receives 1MB file from EC2
2. S3 → KMS: GenerateDataKey (requires kms:GenerateDataKey permission)
3. KMS → S3: Plaintext key + Encrypted key
4. S3 encrypts 1MB file with plaintext key (AES-256)
5. S3 stores:
   - Encrypted 1MB file
   - Encrypted data key (in object metadata)
6. S3 discards plaintext key

KMS API calls: 1 (GenerateDataKey)
Permission needed: kms:GenerateDataKey


### Download 1MB File from S3

javascript
const { GetObjectCommand } = require('@aws-sdk/client-s3');

// Download file
const response = await s3.send(new GetObjectCommand({
  Bucket: 'my-bucket',
  Key: 'file.dat'
}));

const content = await response.Body.transformToByteArray();


Behind the scenes:
1. EC2 requests file from S3
2. S3 retrieves:
   - Encrypted 1MB file
   - Encrypted data key (from metadata)
3. S3 → KMS: Decrypt(encrypted data key) (requires kms:Decrypt permission)
4. KMS → S3: Plaintext data key
5. S3 decrypts 1MB file with plaintext key
6. S3 → EC2: Decrypted 1MB file
7. S3 discards plaintext key

KMS API calls: 1 (Decrypt)
Permission needed: kms:Decrypt


━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━


## Required IAM Permissions

### For EC2 to Upload to S3

json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "s3:PutObject"
      ],
      "Resource": "arn:aws:s3:::my-bucket/*"
    },
    {
      "Effect": "Allow",
      "Action": [
        "kms:GenerateDataKey"
      ],
      "Resource": "arn:aws:kms:us-east-1:ACCOUNT-ID:key/KEY-ID"
    }
  ]
}


### For EC2 to Download from S3

json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "s3:GetObject"
      ],
      "Resource": "arn:aws:s3:::my-bucket/*"
    },
    {
      "Effect": "Allow",
      "Action": [
        "kms:Decrypt"
      ],
      "Resource": "arn:aws:kms:us-east-1:ACCOUNT-ID:key/KEY-ID"
    }
  ]
}


### For Both Upload and Download

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
        "kms:GenerateDataKey",
        "kms:Decrypt"
      ],
      "Resource": "arn:aws:kms:us-east-1:ACCOUNT-ID:key/KEY-ID"
    }
  ]
}


Note: kms:Encrypt is NOT needed for S3 operations!

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━


## Comparison Table

| Permission | Used By | Purpose | S3 Upload | S3 Download | Direct Use |
|------------|---------|---------|-----------|-------------|------------|
| kms:GenerateDataKey | S3, Application | Generate data key for envelope encryption | ✅ Yes | ❌ No | For large files |
| kms:Decrypt | S3, Application | Decrypt data key or ciphertext | ❌ No | ✅ Yes | For decryption |
| kms:Encrypt | Application only | Encrypt small data directly | ❌ No | ❌ No | For small secrets |

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━


## What Happens Without Permissions

### Missing kms:GenerateDataKey

javascript
// Try to upload without kms:GenerateDataKey permission
await s3.send(new PutObjectCommand({
  Bucket: 'my-bucket',
  Key: 'file.dat',
  Body: fileContent,
  ServerSideEncryption: 'aws:kms',
  SSEKMSKeyId: 'alias/my-s3-key'
}));

// Error:
// AccessDeniedException: User is not authorized to perform: 
// kms:GenerateDataKey on resource: arn:aws:kms:...


### Missing kms:Decrypt

javascript
// Try to download without kms:Decrypt permission
await s3.send(new GetObjectCommand({
  Bucket: 'my-bucket',
  Key: 'file.dat'
}));

// Error:
// AccessDeniedException: User is not authorized to perform: 
// kms:Decrypt on resource: arn:aws:kms:...


━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━


## When You Would Use kms:Encrypt

Not for S3, but for application-level encryption:

javascript
const { EncryptCommand, DecryptCommand } = require('@aws-sdk/client-kms');

// Encrypt small secret (password, API key)
async function encryptSecret(secret) {
  const response = await kms.send(new EncryptCommand({
    KeyId: 'alias/my-key',
    Plaintext: Buffer.from(secret)  // Max 4KB
  }));
  
  return response.CiphertextBlob;
}

// Decrypt secret
async function decryptSecret(encrypted) {
  const response = await kms.send(new DecryptCommand({
    CiphertextBlob: encrypted
  }));
  
  return response.Plaintext.toString();
}

// Usage: Store encrypted password in database
const encryptedPassword = await encryptSecret('MyPassword123');
await db.query('INSERT INTO users (username, password) VALUES (?, ?)', 
  ['john', encryptedPassword]);

// Later: Retrieve and decrypt
const user = await db.query('SELECT * FROM users WHERE username = ?', ['john']);
const password = await decryptSecret(user.password);


Permissions needed:
json
{
  "Effect": "Allow",
  "Action": [
    "kms:Encrypt",
    "kms:Decrypt"
  ],
  "Resource": "arn:aws:kms:us-east-1:ACCOUNT-ID:key/KEY-ID"
}


━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━


## Summary

### For S3 with KMS Encryption:

| Operation | KMS Permission Needed | Why |
|-----------|----------------------|-----|
| Upload file | kms:GenerateDataKey | S3 generates data key to encrypt file |
| Download file | kms:Decrypt | S3 decrypts data key to decrypt file |
| Both | kms:GenerateDataKey + kms:Decrypt | Full read/write access |

### kms:Encrypt is NOT used by S3

- Only for direct encryption of small data (<4KB)
- Used by applications, not AWS services
- More expensive and slower than envelope encryption

For your EC2 → S3 use case, you only need:
json
{
  "Action": [
    "kms:GenerateDataKey",  // For uploads
    "kms:Decrypt"           // For downloads
  ]
}