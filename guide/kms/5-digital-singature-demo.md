## Digital Signature with KMS

### What is Digital Signature?

Digital signature proves:
1. Authenticity - Document came from you
2. Integrity - Document wasn't modified
3. Non-repudiation - You can't deny signing it

How it works:
Signing (Private Key):
Document → Hash → Sign with Private Key → Signature

Verification (Public Key):
Document + Signature → Verify with Public Key → Valid/Invalid


━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━


## Complete Example: Software Release Signing

### Scenario
- Company releases software updates
- Users need to verify updates are authentic
- Prevent malware from impersonating updates

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━


### Step 1: Create Asymmetric Key for Signing

bash
# Create RSA key for signing
aws kms create-key \
  --description "Software signing key" \
  --key-spec RSA_2048 \
  --key-usage SIGN_VERIFY

# Output: KeyId: 1234abcd-12ab-34cd-56ef-1234567890ab

# Create alias
aws kms create-alias \
  --alias-name alias/software-signing-key \
  --target-key-id 1234abcd-12ab-34cd-56ef-1234567890ab


Note: Use SIGN_VERIFY (not ENCRYPT_DECRYPT)

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━


### Step 2: Sign Software Release (Private Key)

javascript
// sign-release.js - Run by company (has AWS access)
const { KMSClient, SignCommand, GetPublicKeyCommand } = require('@aws-sdk/client-kms');
const fs = require('fs');
const crypto = require('crypto');

const kms = new KMSClient({ region: 'us-east-1' });

async function signSoftwareRelease(filePath) {
  // 1. Read software file
  const fileData = fs.readFileSync(filePath);
  console.log(`Signing file: ${filePath}`);
  console.log(`File size: ${fileData.length} bytes`);
  
  // 2. Create hash of file (SHA-256)
  const hash = crypto.createHash('sha256').update(fileData).digest();
  console.log(`File hash: ${hash.toString('hex')}`);
  
  // 3. Sign hash with KMS private key
  const signResponse = await kms.send(new SignCommand({
    KeyId: 'alias/software-signing-key',
    Message: hash,
    MessageType: 'DIGEST',  // We're signing a hash
    SigningAlgorithm: 'RSASSA_PSS_SHA_256'
  }));
  
  const signature = signResponse.Signature;
  console.log(`Signature: ${signature.toString('base64')}`);
  
  // 4. Save signature to file
  fs.writeFileSync(`${filePath}.sig`, signature);
  console.log(`✓ Signature saved to ${filePath}.sig`);
  
  return signature;
}

// Sign the release
signSoftwareRelease('app-v1.0.0.zip');


Output:
Signing file: app-v1.0.0.zip
File size: 10485760 bytes
File hash: a3c5f8d9e2b1...
Signature: aGVsbG8gd29ybGQ...
✓ Signature saved to app-v1.0.0.zip.sig


What happens:
Company Server:
1. Reads app-v1.0.0.zip
2. Creates SHA-256 hash
3. KMS signs hash with private key
4. Saves signature to app-v1.0.0.zip.sig

Private key NEVER leaves KMS!


━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━


### Step 3: Export Public Key for Distribution

javascript
// export-public-key.js - Run once
const { KMSClient, GetPublicKeyCommand } = require('@aws-sdk/client-kms');
const fs = require('fs');
const crypto = require('crypto');

const kms = new KMSClient({ region: 'us-east-1' });

async function exportPublicKey() {
  const response = await kms.send(new GetPublicKeyCommand({
    KeyId: 'alias/software-signing-key'
  }));
  
  // Convert to PEM format
  const publicKeyPem = crypto.createPublicKey({
    key: response.PublicKey,
    format: 'der',
    type: 'spki'
  }).export({ type: 'spki', format: 'pem' });
  
  fs.writeFileSync('public_key.pem', publicKeyPem);
  console.log('✓ Public key exported to public_key.pem');
  console.log('Distribute this with your software');
  
  return publicKeyPem;
}

exportPublicKey();


Output (public_key.pem):
-----BEGIN PUBLIC KEY-----
MIIBIjANBgkqhkiG9w0BAQEFAAOCAQ8AMIIBCgKCAQEA...
-----END PUBLIC KEY-----


Distribute:
- Embed in software installer
- Post on company website
- Include in documentation

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━


### Step 4: Verify Signature (Public Key - User Side)

javascript
// verify-release.js - Run by user (no AWS access needed)
const crypto = require('crypto');
const fs = require('fs');

function verifySignature(filePath, signaturePath, publicKeyPath) {
  // 1. Read files
  const fileData = fs.readFileSync(filePath);
  const signature = fs.readFileSync(signaturePath);
  const publicKey = fs.readFileSync(publicKeyPath, 'utf8');
  
  console.log(`Verifying: ${filePath}`);
  
  // 2. Create hash of file
  const hash = crypto.createHash('sha256').update(fileData).digest();
  console.log(`File hash: ${hash.toString('hex')}`);
  
  // 3. Verify signature with public key
  const verify = crypto.createVerify('RSA-SHA256');
  verify.update(hash);
  verify.end();
  
  const isValid = verify.verify(
    {
      key: publicKey,
      padding: crypto.constants.RSA_PKCS1_PSS_PADDING,
      saltLength: crypto.constants.RSA_PSS_SALTLEN_DIGEST
    },
    signature
  );
  
  if (isValid) {
    console.log('✅ Signature VALID - Software is authentic');
    console.log('✅ File has not been tampered with');
    return true;
  } else {
    console.log('❌ Signature INVALID - DO NOT INSTALL');
    console.log('❌ File may be malware or corrupted');
    return false;
  }
}

// User verifies before installing
const isValid = verifySignature(
  'app-v1.0.0.zip',
  'app-v1.0.0.zip.sig',
  'public_key.pem'
);

if (isValid) {
  console.log('\nProceeding with installation...');
} else {
  console.log('\nInstallation aborted!');
  process.exit(1);
}


Output (Valid):
Verifying: app-v1.0.0.zip
File hash: a3c5f8d9e2b1...
✅ Signature VALID - Software is authentic
✅ File has not been tampered with

Proceeding with installation...


Output (Invalid - File Modified):
Verifying: app-v1.0.0.zip
File hash: b4d6g9e3c2f2...  (different!)
❌ Signature INVALID - DO NOT INSTALL
❌ File may be malware or corrupted

Installation aborted!


━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━


## Complete Workflow Diagram

┌─────────────────────────────────────────────────────────────┐
│ Company (Has AWS Access)                                     │
└─────────────────────────────────────────────────────────────┘

    1. Create Software Release
    ┌─────────────────────────┐
    │ app-v1.0.0.zip          │
    │ (10 MB)                 │
    └─────────────────────────┘
                │
                ▼ Hash (SHA-256)
    ┌─────────────────────────┐
    │ Hash: a3c5f8d9e2b1...   │
    └─────────────────────────┘
                │
                ▼ Sign with KMS Private Key
    ┌─────────────────────────┐
    │ KMS (Private Key)       │
    │ Signs hash              │
    └─────────────────────────┘
                │
                ▼ Returns Signature
    ┌─────────────────────────┐
    │ app-v1.0.0.zip.sig      │
    │ (Signature)             │
    └─────────────────────────┘

    2. Distribute
    ┌─────────────────────────┐
    │ app-v1.0.0.zip          │ ◄─── Software
    │ app-v1.0.0.zip.sig      │ ◄─── Signature
    │ public_key.pem          │ ◄─── Public Key
    └─────────────────────────┘

┌─────────────────────────────────────────────────────────────┐
│ User (No AWS Access)                                         │
└─────────────────────────────────────────────────────────────┘

    3. Download Files
    ┌─────────────────────────┐
    │ app-v1.0.0.zip          │
    │ app-v1.0.0.zip.sig      │
    │ public_key.pem          │
    └─────────────────────────┘
                │
                ▼ Hash Downloaded File
    ┌─────────────────────────┐
    │ Hash: a3c5f8d9e2b1...   │
    └─────────────────────────┘
                │
                ▼ Verify with Public Key
    ┌─────────────────────────┐
    │ Verify Signature        │
    │ (Offline, No AWS)       │
    └─────────────────────────┘
                │
                ▼
    ┌─────────────────────────┐
    │ ✅ Valid → Install      │
    │ ❌ Invalid → Abort      │
    └─────────────────────────┘


━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━


## Example 2: API Request Signing

### Scenario: Secure API Communication

javascript
// client.js - Sign API request
const { KMSClient, SignCommand } = require('@aws-sdk/client-kms');
const axios = require('axios');
const crypto = require('crypto');

const kms = new KMSClient({ region: 'us-east-1' });

async function makeSignedRequest(endpoint, data) {
  // 1. Create request payload
  const payload = JSON.stringify(data);
  const timestamp = Date.now();
  const message = `${endpoint}:${timestamp}:${payload}`;
  
  // 2. Hash message
  const hash = crypto.createHash('sha256').update(message).digest();
  
  // 3. Sign with KMS
  const signResponse = await kms.send(new SignCommand({
    KeyId: 'alias/api-signing-key',
    Message: hash,
    MessageType: 'DIGEST',
    SigningAlgorithm: 'RSASSA_PSS_SHA_256'
  }));
  
  // 4. Send request with signature
  const response = await axios.post(endpoint, data, {
    headers: {
      'X-Signature': signResponse.Signature.toString('base64'),
      'X-Timestamp': timestamp
    }
  });
  
  return response.data;
}

// Usage
makeSignedRequest('https://api.example.com/transfer', {
  from: 'account-123',
  to: 'account-456',
  amount: 1000
});


javascript
// server.js - Verify API request
const express = require('express');
const crypto = require('crypto');
const fs = require('fs');

const app = express();
app.use(express.json());

const publicKey = fs.readFileSync('public_key.pem', 'utf8');

app.post('/transfer', (req, res) => {
  const signature = Buffer.from(req.headers['x-signature'], 'base64');
  const timestamp = req.headers['x-timestamp'];
  
  // 1. Recreate message
  const payload = JSON.stringify(req.body);
  const message = `/transfer:${timestamp}:${payload}`;
  const hash = crypto.createHash('sha256').update(message).digest();
  
  // 2. Verify signature
  const verify = crypto.createVerify('RSA-SHA256');
  verify.update(hash);
  verify.end();
  
  const isValid = verify.verify(
    {
      key: publicKey,
      padding: crypto.constants.RSA_PKCS1_PSS_PADDING,
      saltLength: crypto.constants.RSA_PSS_SALTLEN_DIGEST
    },
    signature
  );
  
  if (!isValid) {
    return res.status(401).json({ error: 'Invalid signature' });
  }
  
  // 3. Check timestamp (prevent replay attacks)
  if (Date.now() - timestamp > 60000) {  // 1 minute
    return res.status(401).json({ error: 'Request expired' });
  }
  
  // 4. Process request
  console.log('✅ Signature valid, processing transfer');
  res.json({ success: true });
});

app.listen(3000);


━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━


## Example 3: Document Signing

javascript
// sign-document.js
const { KMSClient, SignCommand } = require('@aws-sdk/client-kms');
const fs = require('fs');
const crypto = require('crypto');

const kms = new KMSClient({ region: 'us-east-1' });

async function signDocument(documentPath, signerName) {
  const document = fs.readFileSync(documentPath, 'utf8');
  
  // Add metadata
  const signedDocument = {
    content: document,
    signer: signerName,
    timestamp: new Date().toISOString(),
    version: '1.0'
  };
  
  // Hash document
  const hash = crypto.createHash('sha256')
    .update(JSON.stringify(signedDocument))
    .digest();
  
  // Sign with KMS
  const signResponse = await kms.send(new SignCommand({
    KeyId: 'alias/document-signing-key',
    Message: hash,
    MessageType: 'DIGEST',
    SigningAlgorithm: 'RSASSA_PSS_SHA_256'
  }));
  
  // Create signed document package
  const signedPackage = {
    ...signedDocument,
    signature: signResponse.Signature.toString('base64')
  };
  
  fs.writeFileSync(
    `${documentPath}.signed.json`,
    JSON.stringify(signedPackage, null, 2)
  );
  
  console.log('✓ Document signed');
  console.log(`Signer: ${signerName}`);
  console.log(`Timestamp: ${signedDocument.timestamp}`);
}

signDocument('contract.txt', 'John Doe');


Output (contract.txt.signed.json):
json
{
  "content": "This is a legal contract...",
  "signer": "John Doe",
  "timestamp": "2026-02-08T20:34:51.749Z",
  "version": "1.0",
  "signature": "aGVsbG8gd29ybGQ..."
}


━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━


## IAM Permissions

### For Signing (Company/Server)

json
{
  "Version": "2012-10-17",
  "Statement": [{
    "Effect": "Allow",
    "Action": [
      "kms:Sign",
      "kms:GetPublicKey"
    ],
    "Resource": "arn:aws:kms:us-east-1:ACCOUNT-ID:key/KEY-ID"
  }]
}


### For Verification (Users)

No AWS permissions needed!
- Users only need public key
- Verification done offline
- No KMS API calls

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━


## Summary

| Aspect | Details |
|--------|---------|
| Private Key | Signs (stays in KMS) |
| Public Key | Verifies (distributed freely) |
| Use Cases | Software releases, API requests, documents |
| Algorithms | RSASSA_PSS_SHA_256, RSASSA_PKCS1_V1_5_SHA_256 |
| Permissions | kms:Sign (signing), kms:GetPublicKey (export) |
| Verification | Offline, no AWS access needed |

Key Benefits:
- ✅ Proves authenticity
- ✅ Detects tampering
- ✅ Non-repudiation
- ✅ Private key never leaves KMS
- ✅ Users verify offline

Digital signatures are essential for software distribution, API security, and document signing.