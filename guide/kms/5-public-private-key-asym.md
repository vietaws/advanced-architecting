## Asymmetric Key: Public Key and Private Key Detailed Explanation

### Key Concept

Asymmetric encryption uses TWO keys:
- **Public Key** - Can be shared with anyone, used to ENCRYPT
- **Private Key** - Must be kept secret, used to DECRYPT

Public Key (shareable):
├── Encrypts data
└── Anyone can use it

Private Key (secret, stays in KMS):
├── Decrypts data
└── Only KMS can use it


━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━


## How It Works

### Visual Flow

Encryption (Public Key):
Plaintext → [Public Key] → Ciphertext

Decryption (Private Key):
Ciphertext → [Private Key] → Plaintext

Key Point: Data encrypted with public key can ONLY be decrypted with private key


━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━


## Complete Example: Mobile App → AWS Server

### Scenario
- Mobile app needs to send sensitive data to AWS
- Mobile app encrypts data locally (offline)
- AWS server decrypts data

### Step 1: Create Asymmetric Key in KMS

bash
# Create RSA asymmetric key
aws kms create-key \
  --description "Mobile app encryption key" \
  --key-spec RSA_2048 \
  --key-usage ENCRYPT_DECRYPT

# Output: KeyId: 1234abcd-12ab-34cd-56ef-1234567890ab

# Create alias
aws kms create-alias \
  --alias-name alias/mobile-app-key \
  --target-key-id 1234abcd-12ab-34cd-56ef-1234567890ab


What KMS creates:
KMS Key Pair:
├── Public Key (RSA 2048-bit)
│   └── Can be exported and shared
└── Private Key (RSA 2048-bit)
    └── NEVER leaves KMS (stays in HSM)


━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━


### Step 2: Export Public Key

javascript
const { KMSClient, GetPublicKeyCommand } = require('@aws-sdk/client-kms');
const fs = require('fs');

const kms = new KMSClient({ region: 'us-east-1' });

// Get public key from KMS
async function exportPublicKey() {
  const response = await kms.send(new GetPublicKeyCommand({
    KeyId: 'alias/mobile-app-key'
  }));
  
  console.log('Public Key (DER format):', response.PublicKey);
  console.log('Key Usage:', response.KeyUsage);  // ENCRYPT_DECRYPT
  console.log('Key Spec:', response.KeySpec);    // RSA_2048
  
  // Save public key to file
  fs.writeFileSync('public_key.der', response.PublicKey);
  
  // Convert to PEM format (human-readable)
  const crypto = require('crypto');
  const publicKeyPem = crypto.createPublicKey({
    key: response.PublicKey,
    format: 'der',
    type: 'spki'
  }).export({ type: 'spki', format: 'pem' });
  
  fs.writeFileSync('public_key.pem', publicKeyPem);
  console.log('Public key exported to public_key.pem');
  
  return publicKeyPem;
}

exportPublicKey();


Output (public_key.pem):
-----BEGIN PUBLIC KEY-----
MIIBIjANBgkqhkiG9w0BAQEFAAOCAQ8AMIIBCgKCAQEAx5...
...
-----END PUBLIC KEY-----


This public key can be:
- ✅ Shared publicly
- ✅ Embedded in mobile apps
- ✅ Distributed to partners
- ✅ Posted on website
- ✅ No security risk

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━


### Step 3: Mobile App Encrypts Data (Using Public Key)

javascript
// mobile-app.js (runs on user's phone, offline)
const crypto = require('crypto');
const fs = require('fs');

// Load public key (embedded in app or downloaded once)
const publicKey = fs.readFileSync('public_key.pem', 'utf8');

// Encrypt sensitive data with public key
function encryptWithPublicKey(data) {
  const encrypted = crypto.publicEncrypt(
    {
      key: publicKey,
      padding: crypto.constants.RSA_PKCS1_OAEP_PADDING,
      oaepHash: 'sha256'
    },
    Buffer.from(data)
  );
  
  return encrypted;
}

// User enters credit card
const creditCard = '4111-1111-1111-1111';
const encryptedCC = encryptWithPublicKey(creditCard);

console.log('Original:', creditCard);
console.log('Encrypted:', encryptedCC.toString('base64'));

// Send encrypted data to server
await fetch('https://api.example.com/payment', {
  method: 'POST',
  body: JSON.stringify({
    encryptedData: encryptedCC.toString('base64')
  })
});


What happens:
Mobile App:
1. Has public key (embedded or downloaded)
2. User enters: "4111-1111-1111-1111"
3. Encrypts with public key
4. Result: "aGVsbG8gd29ybGQ..." (base64 encrypted data)
5. Sends to server

Important: Mobile app CANNOT decrypt this data!
Only AWS server with private key can decrypt.


━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━


### Step 4: AWS Server Decrypts Data (Using Private Key in KMS)

javascript
// server.js (runs on AWS EC2/Lambda)
const { KMSClient, DecryptCommand } = require('@aws-sdk/client-kms');
const express = require('express');

const app = express();
const kms = new KMSClient({ region: 'us-east-1' });

app.use(express.json());

// Decrypt with KMS private key
async function decryptWithPrivateKey(encryptedData) {
  const response = await kms.send(new DecryptCommand({
    KeyId: 'alias/mobile-app-key',
    CiphertextBlob: Buffer.from(encryptedData, 'base64'),
    EncryptionAlgorithm: 'RSAES_OAEP_SHA_256'
  }));
  
  return response.Plaintext.toString();
}

// API endpoint
app.post('/payment', async (req, res) => {
  try {
    const { encryptedData } = req.body;
    
    console.log('Received encrypted data:', encryptedData);
    
    // Decrypt with KMS (private key never leaves KMS)
    const creditCard = await decryptWithPrivateKey(encryptedData);
    
    console.log('Decrypted credit card:', creditCard);
    // Output: "4111-1111-1111-1111"
    
    // Process payment
    await processPayment(creditCard);
    
    res.json({ success: true });
  } catch (error) {
    console.error('Decryption failed:', error);
    res.status(400).json({ error: 'Invalid data' });
  }
});

app.listen(3000);


What happens:
AWS Server:
1. Receives encrypted data from mobile app
2. Calls KMS: "Decrypt this with private key"
3. KMS uses private key (never leaves KMS)
4. KMS returns decrypted data
5. Server processes payment

Important: Private key NEVER leaves KMS!
Server never sees the private key.


━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━


## Detailed Flow Diagram

┌─────────────────────────────────────────────────────────────┐
│ Step 1: Create Key Pair in KMS                              │
└─────────────────────────────────────────────────────────────┘
                            │
                            ▼
                    ┌───────────────┐
                    │   KMS Key     │
                    ├───────────────┤
                    │ Public Key    │ ◄─── Can export
                    │ Private Key   │ ◄─── NEVER leaves KMS
                    └───────────────┘

┌─────────────────────────────────────────────────────────────┐
│ Step 2: Export Public Key                                   │
└─────────────────────────────────────────────────────────────┘
                            │
                            ▼
                    ┌───────────────┐
                    │  Public Key   │
                    │  (PEM file)   │
                    └───────────────┘
                            │
                            ▼
                    Distribute to:
                    - Mobile apps
                    - Partners
                    - Websites

┌─────────────────────────────────────────────────────────────┐
│ Step 3: Mobile App Encrypts (Offline)                       │
└─────────────────────────────────────────────────────────────┘

    Mobile App (User's Phone)
    ┌─────────────────────────┐
    │ Plaintext:              │
    │ "4111-1111-1111-1111"   │
    └─────────────────────────┘
                │
                ▼ Encrypt with Public Key
    ┌─────────────────────────┐
    │ Ciphertext:             │
    │ "aGVsbG8gd29ybGQ..."    │
    └─────────────────────────┘
                │
                ▼ Send to Server
    ┌─────────────────────────┐
    │ HTTPS POST              │
    │ /payment                │
    └─────────────────────────┘

┌─────────────────────────────────────────────────────────────┐
│ Step 4: AWS Server Decrypts (Using KMS Private Key)         │
└─────────────────────────────────────────────────────────────┘

    AWS Server (EC2/Lambda)
    ┌─────────────────────────┐
    │ Receives:               │
    │ "aGVsbG8gd29ybGQ..."    │
    └─────────────────────────┘
                │
                ▼ Call KMS Decrypt
    ┌─────────────────────────┐
    │ KMS (Private Key)       │
    │ Decrypts internally     │
    └─────────────────────────┘
                │
                ▼ Returns Plaintext
    ┌─────────────────────────┐
    │ Plaintext:              │
    │ "4111-1111-1111-1111"   │
    └─────────────────────────┘


━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━


## Key Properties

### Public Key

Can be used to:
- ✅ Encrypt data
- ✅ Verify signatures
- ❌ Decrypt data (impossible!)
- ❌ Create signatures (impossible!)

Security:
- ✅ Safe to share publicly
- ✅ Can be embedded in apps
- ✅ Can be posted online
- ✅ No risk if stolen

Example:
javascript
// Anyone can encrypt with public key
const encrypted = crypto.publicEncrypt(publicKey, Buffer.from('secret'));

// But CANNOT decrypt
const decrypted = crypto.publicDecrypt(publicKey, encrypted);
// Error: Cannot decrypt with public key!


### Private Key

Can be used to:
- ✅ Decrypt data
- ✅ Create signatures
- ❌ Encrypt data (technically possible but not the pattern)

Security:
- ❌ NEVER share
- ❌ NEVER export from KMS
- ❌ NEVER store outside KMS
- ✅ Stays in KMS HSM forever

In KMS:
javascript
// Private key NEVER leaves KMS
// You can only ask KMS to use it

// Decrypt (KMS uses private key internally)
await kms.send(new DecryptCommand({
  KeyId: 'alias/mobile-app-key',
  CiphertextBlob: encrypted
}));
// KMS uses private key, returns plaintext
// You never see the private key!


━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━


## Complete Working Example

### Setup Script

javascript
// setup.js - Run once to create key and export public key
const { KMSClient, CreateKeyCommand, CreateAliasCommand, GetPublicKeyCommand } = require('@aws-sdk/client-kms');
const fs = require('fs');
const crypto = require('crypto');

const kms = new KMSClient({ region: 'us-east-1' });

async function setup() {
  // 1. Create asymmetric key
  console.log('Creating asymmetric key...');
  const keyResponse = await kms.send(new CreateKeyCommand({
    Description: 'Mobile app encryption key',
    KeySpec: 'RSA_2048',
    KeyUsage: 'ENCRYPT_DECRYPT'
  }));
  
  const keyId = keyResponse.KeyMetadata.KeyId;
  console.log('✓ Key created:', keyId);
  
  // 2. Create alias
  await kms.send(new CreateAliasCommand({
    AliasName: 'alias/mobile-app-key',
    TargetKeyId: keyId
  }));
  console.log('✓ Alias created: alias/mobile-app-key');
  
  // 3. Export public key
  const publicKeyResponse = await kms.send(new GetPublicKeyCommand({
    KeyId: 'alias/mobile-app-key'
  }));
  
  const publicKeyPem = crypto.createPublicKey({
    key: publicKeyResponse.PublicKey,
    format: 'der',
    type: 'spki'
  }).export({ type: 'spki', format: 'pem' });
  
  fs.writeFileSync('public_key.pem', publicKeyPem);
  console.log('✓ Public key exported to public_key.pem');
  
  console.log('\n=== Setup Complete ===');
  console.log('Public key can be distributed to mobile apps');
  console.log('Private key stays in KMS (never exported)');
}

setup();


### Mobile App (Client)

javascript
// mobile-app.js - Runs on user's device
const crypto = require('crypto');
const fs = require('fs');
const axios = require('axios');

// Load public key (embedded in app)
const publicKey = fs.readFileSync('public_key.pem', 'utf8');

async function sendSensitiveData() {
  // User enters sensitive data
  const sensitiveData = {
    creditCard: '4111-1111-1111-1111',
    cvv: '123',
    ssn: '123-45-6789'
  };
  
  console.log('Original data:', sensitiveData);
  
  // Encrypt with public key (offline, no AWS needed)
  const encrypted = crypto.publicEncrypt(
    {
      key: publicKey,
      padding: crypto.constants.RSA_PKCS1_OAEP_PADDING,
      oaepHash: 'sha256'
    },
    Buffer.from(JSON.stringify(sensitiveData))
  );
  
  console.log('Encrypted:', encrypted.toString('base64'));
  
  // Send to server
  const response = await axios.post('http://localhost:3000/process', {
    encryptedData: encrypted.toString('base64')
  });
  
  console.log('Server response:', response.data);
}

sendSensitiveData();


### AWS Server

javascript
// server.js - Runs on AWS EC2/Lambda
const { KMSClient, DecryptCommand } = require('@aws-sdk/client-kms');
const express = require('express');

const app = express();
const kms = new KMSClient({ region: 'us-east-1' });

app.use(express.json());

app.post('/process', async (req, res) => {
  try {
    const { encryptedData } = req.body;
    
    console.log('Received encrypted data');
    
    // Decrypt with KMS (private key in KMS)
    const decryptResponse = await kms.send(new DecryptCommand({
      KeyId: 'alias/mobile-app-key',
      CiphertextBlob: Buffer.from(encryptedData, 'base64'),
      EncryptionAlgorithm: 'RSAES_OAEP_SHA_256'
    }));
    
    const decryptedData = JSON.parse(decryptResponse.Plaintext.toString());
    
    console.log('Decrypted data:', decryptedData);
    // Output: { creditCard: '4111-1111-1111-1111', cvv: '123', ssn: '123-45-6789' }
    
    // Process data
    await processPayment(decryptedData);
    
    res.json({ success: true, message: 'Data processed securely' });
  } catch (error) {
    console.error('Error:', error);
    res.status(400).json({ error: 'Decryption failed' });
  }
});

app.listen(3000, () => {
  console.log('Server running on port 3000');
  console.log('Private key stays in KMS - never exposed');
});


━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━


## Security Benefits

### Why This is Secure

1. Public key can be stolen - no problem:
Attacker steals public_key.pem
├── Can encrypt data
└── CANNOT decrypt data (needs private key)

Result: No security breach


2. Private key never leaves KMS:
Private key in KMS HSM
├── Cannot be exported
├── Cannot be viewed
└── Can only be used via API

Result: Even AWS employees can't access it


3. Man-in-the-middle attack:
Attacker intercepts encrypted data
├── Has encrypted ciphertext
├── Has public key
└── CANNOT decrypt (needs private key)

Result: Data remains secure


━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━


## Summary

| Aspect | Public Key | Private Key |
|--------|------------|-------------|
| Location | Anywhere (mobile apps, websites) | KMS only (never leaves) |
| Can Encrypt | ✅ Yes | ❌ No (not the pattern) |
| Can Decrypt | ❌ No | ✅ Yes |
| Can be Shared | ✅ Yes (safe) | ❌ Never |
| Can be Stolen | ✅ No problem | ❌ Catastrophic |
| Used By | Mobile apps, external parties | AWS server only |

Key Concept: Data encrypted with public key can ONLY be decrypted with private key. This enables secure communication without 
sharing secrets.