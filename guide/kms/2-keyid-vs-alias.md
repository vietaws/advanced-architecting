## KMS Key ID vs Alias

### Key ID vs Alias Comparison

| Aspect | Key ID | Alias |
|--------|--------|-------|
| Format | 1234abcd-12ab-34cd-56ef-1234567890ab | alias/my-app-key |
| Cost | $0 (included with key) | $0 (included with key) |
| Uniqueness | Globally unique | Unique per account/region |
| Changeability | Never changes | Can point to different keys |
| Readability | Hard to remember | Human-readable |
| Best for | Programmatic access | Application configuration |

### Cost

Both are FREE - no additional cost for using alias vs key ID

bash
# Create key: $1/month
aws kms create-key --description "My key"

# Create alias: $0 (free)
aws kms create-alias \
  --alias-name alias/my-app-key \
  --target-key-id 1234abcd-12ab-34cd-56ef-1234567890ab

# Total cost: $1/month (same whether you use key ID or alias)


━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━


## Using in Applications

### Using Key ID (Not Recommended)

javascript
// ❌ Hardcoded key ID - difficult to rotate
const { KMSClient, EncryptCommand } = require('@aws-sdk/client-kms');

const kms = new KMSClient({ region: 'us-east-1' });

async function encryptData(plaintext) {
  const command = new EncryptCommand({
    KeyId: '1234abcd-12ab-34cd-56ef-1234567890ab',  // Hard to remember
    Plaintext: Buffer.from(plaintext)
  });
  
  return await kms.send(command);
}


Problems:
- Hard to remember
- Must update code to change keys
- Difficult to manage multiple environments

### Using Alias (Recommended)

javascript
// ✅ Using alias - easy to rotate
const { KMSClient, EncryptCommand } = require('@aws-sdk/client-kms');

const kms = new KMSClient({ region: 'us-east-1' });

async function encryptData(plaintext) {
  const command = new EncryptCommand({
    KeyId: 'alias/my-app-key',  // Human-readable
    Plaintext: Buffer.from(plaintext)
  });
  
  return await kms.send(command);
}


Benefits:
- Easy to read and remember
- Can change underlying key without code changes
- Different aliases for different environments

### Environment-Specific Aliases

javascript
// config.js
const config = {
  development: {
    kmsKeyAlias: 'alias/dev-app-key'
  },
  staging: {
    kmsKeyAlias: 'alias/staging-app-key'
  },
  production: {
    kmsKeyAlias: 'alias/prod-app-key'
  }
};

// app.js
const keyAlias = config[process.env.NODE_ENV].kmsKeyAlias;

async function encryptData(plaintext) {
  const command = new EncryptCommand({
    KeyId: keyAlias,  // Automatically uses correct key per environment
    Plaintext: Buffer.from(plaintext)
  });
  
  return await kms.send(command);
}