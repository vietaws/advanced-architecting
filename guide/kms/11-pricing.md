## KMS Key Pricing - Prorated Hourly Charges

### Monthly Cost Breakdown

Customer Managed Key: $1.00 per month

Prorated hourly rate:
$1.00 per month ÷ 730 hours per month* = $0.00137 per hour

*AWS uses 730 hours (365 days × 24 hours ÷ 12 months)


━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━


## How Prorating Works

### Example 1: Key Exists for 10 Days

Key created: February 1, 2026
Key deleted: February 10, 2026
Duration: 10 days = 240 hours

Cost: 240 hours × $0.00137/hour = $0.33


### Example 2: Key Exists for 15 Hours

Key created: February 8, 2026 at 10:00 AM
Key deleted: February 9, 2026 at 1:00 AM
Duration: 15 hours

Cost: 15 hours × $0.00137/hour = $0.02


### Example 3: Key Exists for Full Month

Key created: February 1, 2026
Key exists: All of February (28 days = 672 hours)

Cost: 672 hours × $0.00137/hour = $0.92
(Billed as $1.00 for full month)


━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━


## Billing Timeline

### Key Lifecycle Charges

bash
# Create key
aws kms create-key --description "Test key"
# Billing starts immediately

# Time: 0 hours
# Cost: $0.00

# Time: 1 hour
# Cost: $0.00137

# Time: 24 hours (1 day)
# Cost: $0.03

# Time: 168 hours (1 week)
# Cost: $0.23

# Time: 730 hours (1 month)
# Cost: $1.00

# Schedule deletion (7-30 day waiting period)
aws kms schedule-key-deletion \
  --key-id KEY-ID \
  --pending-window-in-days 7

# Billing continues during waiting period!
# 7 days = 168 hours × $0.00137 = $0.23 additional

# After deletion completes
# Billing stops


━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━


## Important Billing Details

### 1. Billing Starts Immediately

bash
# Create key at 10:00 AM
aws kms create-key --description "My key"

# Billing starts: 10:00 AM
# Even if you never use the key!


### 2. Billing Continues During Deletion Waiting Period

bash
# Schedule deletion on Day 1
aws kms schedule-key-deletion \
  --key-id KEY-ID \
  --pending-window-in-days 30

# Key state: PendingDeletion
# Billing: Continues for 30 days!
# Additional cost: 30 days × $0.03/day = $0.90

# To stop billing immediately:
# Cancel deletion, then disable key
aws kms cancel-key-deletion --key-id KEY-ID
aws kms disable-key --key-id KEY-ID
# Billing still continues even when disabled!


### 3. Disabled Keys Still Incur Charges

bash
# Disable key
aws kms disable-key --key-id KEY-ID

# Key state: Disabled
# Billing: Still $1/month!
# Cannot use key, but still charged

# To stop charges: Must delete key


━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━


## Cost Examples

### Scenario 1: Testing Key for 1 Hour

Create key: 10:00 AM
Delete key: 11:00 AM
Duration: 1 hour

Cost: $0.00137


### Scenario 2: Monthly Development Key

Create key: Start of month
Use for: 30 days
Delete: End of month

Cost: $1.00 (full month)


### Scenario 3: Forgot to Delete Key

Create key: January 1
Forgot about it
Discovered: June 1
Duration: 5 months

Cost: 5 × $1.00 = $5.00
(Even if never used!)


### Scenario 4: Multiple Keys

Key 1: Exists all month
Key 2: Created mid-month (15 days)
Key 3: Created last week (7 days)

Cost:
- Key 1: $1.00
- Key 2: 15 days × $0.03/day = $0.45
- Key 3: 7 days × $0.03/day = $0.21
Total: $1.66


━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━


## API Request Charges (Separate from Key Charges)

### Request Pricing

Symmetric keys:
- $0.03 per 10,000 requests

Asymmetric keys:
- $0.15 per 10,000 requests

Prorated:
Symmetric: $0.000003 per request
Asymmetric: $0.000015 per request


### Example: 1,000 Requests

Symmetric:
1,000 requests × $0.000003 = $0.003

Asymmetric:
1,000 requests × $0.000015 = $0.015


━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━


## Total Monthly Cost Example

### Scenario: Production Application

Keys:
- 1 symmetric key (full month): $1.00
- API requests: 1,000,000 encrypt/decrypt

Request cost:
(1,000,000 / 10,000) × $0.03 = $3.00

Total: $1.00 + $3.00 = $4.00/month


━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━


## Cost Optimization Tips

### 1. Delete Unused Keys Immediately

bash
# Don't wait - delete right away
aws kms schedule-key-deletion \
  --key-id KEY-ID \
  --pending-window-in-days 7  # Minimum waiting period

# Cost saved: $0.23 (7 days) vs $0.90 (30 days)


### 2. Use Aliases to Reuse Keys

bash
# ❌ Bad: Create new key for each environment
aws kms create-key --description "Dev key"    # $1/month
aws kms create-key --description "Staging key" # $1/month
aws kms create-key --description "Prod key"   # $1/month
# Total: $3/month

# ✅ Good: Use one key with different aliases
aws kms create-key --description "Shared key"  # $1/month
aws kms create-alias --alias-name alias/dev-key --target-key-id KEY-ID
aws kms create-alias --alias-name alias/staging-key --target-key-id KEY-ID
aws kms create-alias --alias-name alias/prod-key --target-key-id KEY-ID
# Total: $1/month (saved $2/month)


### 3. Monitor Unused Keys

bash
# List all keys
aws kms list-keys

# Check last usage
aws kms describe-key --key-id KEY-ID

# Delete if not used in 30+ days


### 4. Use AWS Managed Keys When Possible

bash
# ✅ Free: AWS managed key
aws s3api put-bucket-encryption \
  --bucket my-bucket \
  --server-side-encryption-configuration '{
    "Rules": [{
      "ApplyServerSideEncryptionByDefault": {
        "SSEAlgorithm": "aws:kms"
      }
    }]
  }'
# Uses aws/s3 key (free)

# ❌ $1/month: Customer managed key
aws s3api put-bucket-encryption \
  --bucket my-bucket \
  --server-side-encryption-configuration '{
    "Rules": [{
      "ApplyServerSideEncryptionByDefault": {
        "SSEAlgorithm": "aws:kms",
        "KMSMasterKeyID": "alias/my-key"
      }
    }]
  }'
# Uses your key ($1/month)


━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━


## Billing Summary

| Item | Cost | Prorated |
|------|------|----------|
| Customer Managed Key | $1.00/month | $0.00137/hour |
| AWS Managed Key | Free | Free |
| Symmetric Requests | $0.03/10K | $0.000003/request |
| Asymmetric Requests | $0.15/10K | $0.000015/request |
| Disabled Key | $1.00/month | Still charged! |
| PendingDeletion Key | $1.00/month | Still charged! |

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━


## Check Your KMS Costs

bash
# View KMS costs for current month
aws ce get-cost-and-usage \
  --time-period Start=2026-02-01,End=2026-02-28 \
  --granularity MONTHLY \
  --metrics BlendedCost \
  --filter file://filter.json

# filter.json
{
  "Dimensions": {
    "Key": "SERVICE",
    "Values": ["AWS Key Management Service"]
  }
}


━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━


## Key Takeaways

1. $1/month = $0.00137/hour (prorated)
2. Billing starts immediately when key is created
3. Billing continues even when key is disabled
4. Billing continues during deletion waiting period (7-30 days)
5. Delete unused keys to stop charges
6. Use AWS managed keys when you don't need custom control (free)

Bottom line: If you create a key and delete it after 1 hour, you pay $0.00137, not $1.00.