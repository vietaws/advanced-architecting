## Key Rotation Explained

### What is Key Rotation?

Key rotation creates a NEW cryptographic key while keeping the OLD key for decryption.

### How It Works

Before Rotation:
Key: key-v1 (active)
├── Encrypts new data
└── Decrypts old data


After Rotation (Automatic):
Key ID: 1234abcd-12ab-34cd-56ef-1234567890ab (same!)
├── key-v2 (active) → Encrypts NEW data
└── key-v1 (archived) → Decrypts OLD data encrypted with v1


Key Point: The Key ID and Alias stay the same!

### Enable Automatic Rotation

bash
# Enable rotation (once per year)
aws kms enable-key-rotation \
  --key-id 1234abcd-12ab-34cd-56ef-1234567890ab

# Check rotation status
aws kms get-key-rotation-status \
  --key-id 1234abcd-12ab-34cd-56ef-1234567890ab


━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━


## Application Impact: ZERO Changes Needed!

### Encryption (Uses Latest Key Version)

javascript
// Before rotation
await kms.send(new EncryptCommand({
  KeyId: 'alias/my-app-key',
  Plaintext: Buffer.from('secret data')
}));
// Uses key-v1

// After rotation (NO CODE CHANGES)
await kms.send(new EncryptCommand({
  KeyId: 'alias/my-app-key',  // Same alias!
  Plaintext: Buffer.from('secret data')
}));
// Automatically uses key-v2


### Decryption (Automatic Version Detection)

javascript
// Decrypt data encrypted with key-v1
await kms.send(new DecryptCommand({
  CiphertextBlob: oldEncryptedData  // No KeyId needed!
}));
// KMS automatically uses key-v1 to decrypt

// Decrypt data encrypted with key-v2
await kms.send(new DecryptCommand({
  CiphertextBlob: newEncryptedData  // No KeyId needed!
}));
// KMS automatically uses key-v2 to decrypt


Magic: Encrypted data contains metadata about which key version was used. KMS automatically selects the correct 
version for decryption.

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━


## Real-World Example

### Timeline

Day 1: Initial Setup
bash
# Create key
aws kms create-key --description "App key"
# Key ID: 1234abcd-12ab-34cd-56ef-1234567890ab

# Create alias
aws kms create-alias \
  --alias-name alias/my-app-key \
  --target-key-id 1234abcd-12ab-34cd-56ef-1234567890ab

# Enable rotation
aws kms enable-key-rotation --key-id 1234abcd-12ab-34cd-56ef-1234567890ab


Day 1-365: Application Encrypts Data
javascript
// Encrypt 1 million records
for (let i = 0; i < 1000000; i++) {
  const encrypted = await kms.send(new EncryptCommand({
    KeyId: 'alias/my-app-key',
    Plaintext: Buffer.from(`record-${i}`)
  }));
  
  await db.save({ id: i, data: encrypted.CiphertextBlob });
}
// All encrypted with key-v1


Day 365: Automatic Rotation Occurs
KMS automatically:
├── Creates key-v2
├── Marks key-v2 as active (for encryption)
├── Keeps key-v1 available (for decryption)
└── Key ID and alias unchanged


Day 366+: Application Continues Normally
javascript
// Decrypt old data (encrypted with key-v1)
const oldRecord = await db.get(500);
const decrypted = await kms.send(new DecryptCommand({
  CiphertextBlob: oldRecord.data  // Encrypted with key-v1
}));
// KMS automatically uses key-v1 ✓

// Encrypt new data (uses key-v2)
const encrypted = await kms.send(new EncryptCommand({
  KeyId: 'alias/my-app-key',  // Same alias!
  Plaintext: Buffer.from('new-record')
}));
// KMS automatically uses key-v2 ✓

// NO CODE CHANGES NEEDED!


━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━


## Manual Key Rotation (Alias Benefit)

### Scenario: Need to rotate immediately (not wait 1 year)

Step 1: Create New Key
bash
# Create new key
aws kms create-key --description "App key v2"
# New Key ID: 5678efgh-56ef-78gh-90ij-5678901234ef


Step 2: Update Alias (Zero Downtime)
bash
# Point alias to new key
aws kms update-alias \
  --alias-name alias/my-app-key \
  --target-key-id 5678efgh-56ef-78gh-90ij-5678901234ef


Step 3: Application Automatically Uses New Key
javascript
// NO CODE CHANGES!
// Encryption now uses new key
await kms.send(new EncryptCommand({
  KeyId: 'alias/my-app-key',  // Now points to new key
  Plaintext: Buffer.from('data')
}));

// Decryption of old data still works
await kms.send(new DecryptCommand({
  CiphertextBlob: oldData  // Encrypted with old key
}));
// KMS automatically uses old key


Step 4: Gradually Re-encrypt Old Data (Optional)
javascript
// Background job to re-encrypt old data
async function reencryptOldData() {
  const oldRecords = await db.query('SELECT * FROM encrypted_data WHERE created_at < ?', [rotationDate]);
  
  for (const record of oldRecords) {
    // Decrypt with old key
    const decrypted = await kms.send(new DecryptCommand({
      CiphertextBlob: record.data
    }));
    
    // Re-encrypt with new key
    const reencrypted = await kms.send(new EncryptCommand({
      KeyId: 'alias/my-app-key',  // New key
      Plaintext: decrypted.Plaintext
    }));
    
    // Update database
    await db.update(record.id, { data: reencrypted.CiphertextBlob });
  }
}


Step 5: Disable Old Key (After Re-encryption)
bash
# Disable old key (can still decrypt existing data)
aws kms disable-key --key-id 1234abcd-12ab-34cd-56ef-1234567890ab

# Or schedule deletion (7-30 days)
aws kms schedule-key-deletion \
  --key-id 1234abcd-12ab-34cd-56ef-1234567890ab \
  --pending-window-in-days 30

## Key Rotation: Automatic vs Manual

### Automatic Rotation

How it works:
bash
aws kms enable-key-rotation --key-id KEY-ID


Characteristics:
- Rotates every 365 days
- Same Key ID
- Old versions kept forever
- Free (no additional cost)
- Zero application changes
- Cannot control timing

Timeline:
Year 1: key-v1 (active)
Year 2: key-v2 (active), key-v1 (decrypt only)
Year 3: key-v3 (active), key-v2 & key-v1 (decrypt only)
...


### Manual Rotation (Using Alias)

How it works:
bash
# Create new key
aws kms create-key

# Update alias
aws kms update-alias --alias-name alias/my-key --target-key-id NEW-KEY-ID


Characteristics:
- Rotate anytime
- Different Key IDs
- Must manage old keys
- $1/month per key
- Zero application changes (if using alias)
- Full control over timing

Timeline:
Month 1: key-1 (active)
Month 6: key-2 (active), key-1 (kept for old data)
Month 12: key-3 (active), key-2 & key-1 (kept for old data)


━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━


## Do You Need to Manage Previous Keys in Application?

### Answer: NO!

KMS handles everything automatically:

javascript
// Your application code (never changes)
async function encrypt(data) {
  return await kms.send(new EncryptCommand({
    KeyId: 'alias/my-key',
    Plaintext: Buffer.from(data)
  }));
}

async function decrypt(ciphertext) {
  return await kms.send(new DecryptCommand({
    CiphertextBlob: ciphertext
    // No KeyId needed - KMS knows which version to use!
  }));
}

// Works for data encrypted with:
// - key-v1 (2 years ago)
// - key-v2 (1 year ago)
// - key-v3 (current)
// Application doesn't care!


### How KMS Knows Which Key Version

Encrypted data structure:
Ciphertext = {
  version: "key-v1",           // Metadata
  keyId: "1234abcd...",        // Key ID
  encryptedData: "..."         // Actual encrypted data
}


When you call decrypt(), KMS:
1. Reads metadata from ciphertext
2. Identifies key version used
3. Uses that version to decrypt
4. Returns plaintext

You never need to track key versions!

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━


## Best Practices

### 1. Always Use Alias in Application Code

javascript
// ✅ GOOD
const KEY_ALIAS = 'alias/prod-app-key';

// ❌ BAD
const KEY_ID = '1234abcd-12ab-34cd-56ef-1234567890ab';


### 2. Enable Automatic Rotation

bash
aws kms enable-key-rotation --key-id KEY-ID


### 3. Use Environment Variables

javascript
// .env
KMS_KEY_ALIAS=alias/prod-app-key

// app.js
const keyAlias = process.env.KMS_KEY_ALIAS;


### 4. Don't Re-encrypt Unless Required

javascript
// ❌ Unnecessary - old data still secure
async function reencryptEverything() {
  // Don't do this unless compliance requires it
}

// ✅ Only re-encrypt if needed
async function reencryptIfRequired() {
  // Only if compliance mandates data encrypted with current key
}


━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━


## Summary

| Question | Answer |
|----------|--------|
| Cost difference? | None - both free |
| Which to use in app? | Alias (easier to manage) |
| What is key rotation? | Creating new key version, keeping old for decryption |
| Need to manage old keys? | No - KMS handles automatically |
| Code changes after rotation? | Zero - works transparently |
| Can decrypt old data? | Yes - forever (automatic rotation) |
| Best practice? | Use alias + enable automatic rotation |

Key Takeaway: Use aliases in your application code, enable automatic rotation, and forget about it. KMS handles all 
the complexity of managing multiple key versions transparently.