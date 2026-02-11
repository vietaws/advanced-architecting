## AWS KMS Pricing Components

### 1. KMS Keys

Customer Managed Keys (CMK):
- **Single-region key:** $1.00/month per key
- **Multi-region primary key:** $1.00/month per key
- **Multi-region replica key:** $1.00/month per replica

AWS Managed Keys:
- **Free** (e.g., aws/s3, aws/ebs, aws/rds)

Important: Each replica in a multi-region key setup is billed separately.

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━


### 2. API Request Pricing

| Request Type | Price | Notes |
|--------------|-------|-------|
| Symmetric encryption/decryption | First 20,000 requests/month: Free<br>$0.03 per 10,000 requests after | Encrypt, Decrypt, 
GenerateDataKey, GenerateDataKeyWithoutPlaintext |
| Asymmetric requests | $0.15 per 10,000 requests | Sign, Verify, GetPublicKey |
| RSA encryption/decryption | $0.15 per 10,000 requests | Encrypt/Decrypt with RSA keys |
| ECC requests | $0.15 per 10,000 requests | Sign/Verify with ECC keys |

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━


### 3. Multi-Region Key Pricing

Example: 2-region setup (us-east-1 + ap-southeast-1)

Keys:
- Primary key in us-east-1: $1.00/month
- Replica key in ap-southeast-1: $1.00/month
- **Total:** $2.00/month per multi-region key

API Requests:
- Requests are charged in the region where they're made
- Each region has its own 20,000 free tier per month
- Cross-region requests are NOT charged differently

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━


## Your Architecture Scenario

### Setup
- **us-east-1:** VPC A, VPC B
- **ap-southeast-1:** VPC C, VPC D, VPC Shared (with KMS)

### Option 1: Single-Region Keys in VPC Shared (ap-southeast-1)

Keys:
- 1 CMK in ap-southeast-1: $1.00/month

VPC Endpoints (already calculated):
- 2 KMS endpoints (2 AZs) in VPC Shared: $14.60/month

API Requests:
- All VPCs (A, B, C, D) make requests to ap-southeast-1 KMS
- First 20,000 requests/month: Free
- After: $0.03 per 10,000 requests

Cross-region considerations:
- VPC A and B (us-east-1) must route through TGW peering to reach KMS in ap-southeast-1
- Adds latency (~50-100ms)
- Incurs TGW data processing fees

Total monthly cost:
- Keys: $1.00
- VPC Endpoints: $14.60
- API requests: Variable (depends on volume)
- **Base cost: $15.60/month**

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━


### Option 2: Multi-Region Keys

Keys:
- Primary key in ap-southeast-1: $1.00/month
- Replica key in us-east-1: $1.00/month
- **Total:** $2.00/month

VPC Endpoints:
- 2 KMS endpoints in VPC Shared (ap-southeast-1): $14.60/month
- 2 KMS endpoints in VPC A or Shared VPC in us-east-1: $14.60/month
- **Total:** $29.20/month

API Requests:
- Each region has 20,000 free requests/month
- VPC A, B use us-east-1 replica (low latency)
- VPC C, D use ap-southeast-1 primary (low latency)
- After free tier: $0.03 per 10,000 requests per region

Benefits:
- Lower latency for us-east-1 VPCs
- No cross-region TGW traffic for KMS requests
- Better disaster recovery

Total monthly cost:
- Keys: $2.00
- VPC Endpoints: $29.20
- API requests: Variable
- **Base cost: $31.20/month**

Savings from reduced TGW traffic:
- Assume 10,000 KMS requests/month from us-east-1 VPCs
- Average request/response: 1 KB
- Monthly data: 10 MB (negligible TGW savings)

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━


## Cost Comparison

| Scenario | Keys | VPC Endpoints | API Requests (100K/month) | TGW Savings | Total |
|----------|------|---------------|---------------------------|-------------|-------|
| Single-region | $1.00 | $14.60 | $0.24 | $0 | $15.84 |
| Multi-region | $2.00 | $29.20 | $0.24 | ~$0 | $31.44 |

Difference: $15.60/month more for multi-region

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━


## API Request Pricing Examples

### Example 1: Low Volume (50,000 requests/month)
- First 20,000: Free
- Remaining 30,000: 30,000 ÷ 10,000 × $0.03 = $0.09
- **Total: $0.09/month**

### Example 2: Medium Volume (500,000 requests/month)
- First 20,000: Free
- Remaining 480,000: 480,000 ÷ 10,000 × $0.03 = $1.44
- **Total: $1.44/month**

### Example 3: High Volume (10 million requests/month)
- First 20,000: Free
- Remaining 9,980,000: 9,980,000 ÷ 10,000 × $0.03 = $29.94
- **Total: $29.94/month**

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━


## Recommendations

### Use Single-Region Keys If:
- Cost is primary concern
- Latency to ap-southeast-1 is acceptable (<100ms)
- Low request volume from us-east-1
- Simple key management preferred

### Use Multi-Region Keys If:
- Low latency required in both regions (<10ms)
- High availability and disaster recovery critical
- Compliance requires regional data residency
- Need to encrypt/decrypt data in multiple regions without cross-region calls
- Request volume justifies the extra $15.60/month

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━


## Additional Considerations

### 1. VPC Endpoint Strategy

Centralized (Current):
- KMS endpoints only in VPC Shared
- Other VPCs route through TGW
- Cost: $14.60/month (single region) or $29.20/month (multi-region)

Distributed:
- KMS endpoints in each VPC
- No TGW routing needed
- Cost: 7 VPCs × 2 AZs × $0.01/hour × 730 = $102.20/month
- **Not recommended** - much more expensive

### 2. KMS Request Optimization

- **Use data keys:** Call GenerateDataKey once, cache for multiple operations
- **Batch operations:** Reduce API calls where possible
- **Client-side caching:** Use AWS Encryption SDK with caching

### 3. Multi-Region Key Benefits Beyond Cost

- **Disaster recovery:** Automatic key replication
- **Global applications:** Same key ID works in all regions
- **Compliance:** Meet data residency requirements
- **Simplified management:** One logical key, multiple regions

### 4. Free Tier

- **20,000 requests/month per region** for symmetric operations
- Applies to each region independently
- Multi-region setup gets 20,000 × 2 = 40,000 free requests total

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━


## Recommendation for Your Architecture

Use single-region keys in ap-southeast-1 because:

1. Cost effective: $15.60/month vs $31.44/month
2. Low cross-region volume: VPC A and B likely have minimal KMS requests
3. Acceptable latency: KMS operations are typically infrequent
4. Simplified management: One key to manage

Upgrade to multi-region if:
- Latency becomes an issue (>100ms unacceptable)
- us-east-1 VPCs make >100,000 KMS requests/month
- Disaster recovery requirements mandate regional redundancy
- Compliance requires regional key availability

For most workloads, the single-region approach is sufficient and cost-effective