## Architecture Summary

us-east-1: TGW owned by Account A, shared to Account B
ap-southeast-1: TGW owned by Account Shared, shared to Accounts C, D, Ingress, Egress

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━


## 1. Number of AWS Transit Gateways

Answer: 2 Transit Gateways

- 1 TGW in us-east-1 (owned by Account A)
- 1 TGW in ap-southeast-1 (owned by Account Shared)

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━


## 2. Number of Transit Gateway Peering Connections

Answer: 1 Peering Connection

- us-east-1 TGW (Account A) ↔ ap-southeast-1 TGW (Account Shared)

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━


## 3. Number of Attachments per Transit Gateway

us-east-1 TGW (Account A): 3 attachments
- VPC A attachment
- VPC B attachment (shared via RAM)
- Peering attachment (to ap-southeast-1 TGW)

ap-southeast-1 TGW (Account Shared): 6 attachments
- VPC Shared attachment
- VPC C attachment (shared via RAM)
- VPC D attachment (shared via RAM)
- VPC Ingress attachment (shared via RAM)
- VPC Egress attachment (shared via RAM)
- Peering attachment (to us-east-1 TGW)

Total: 9 attachments

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━


## Complete Cost Breakdown - All Accounts

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━


### Account A (owns us-east-1 TGW + VPC A)

VPC Attachments:
- VPC A attachment: $36.50/month

Peering:
- Peering attachment (us-east-1 side): $36.50/month

TGW Data Processing (all us-east-1 traffic):
- VPC A ↔ VPC B: 11 GB/day × 30 = 330 GB × $0.02 = $6.60
- VPC A → Shared: 1.2 GB/day × 30 = 36 GB × $0.02 = $0.72
- VPC B → Shared: 2.5 GB/day × 30 = 75 GB × $0.02 = $1.50
- VPC A → VPC C: 13 GB/day × 30 = 390 GB × $0.02 = $7.80
- **Subtotal:** $16.62/month

Cross-Region Data Transfer Out (us-east-1 → ap-southeast-1):
- VPC A → Shared: 36 GB × $0.02 = $0.72
- VPC A → VPC C: 390 GB × $0.02 = $7.80
- VPC B → Shared: 75 GB × $0.02 = $1.50
- **Subtotal:** $10.02/month

Account A Total: $99.64/month

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━


### Account B (VPC B only)

VPC Attachments:
- VPC B attachment to Account A's TGW: $36.50/month

Account B Total: $36.50/month

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━


### Account C (VPC C only)

VPC Attachments:
- VPC C attachment to Account Shared's TGW: $36.50/month

Account C Total: $36.50/month

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━


### Account D (VPC D only)

VPC Attachments:
- VPC D attachment to Account Shared's TGW: $36.50/month

Account D Total: $36.50/month

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━


### Account Shared (owns ap-southeast-1 TGW + VPC Shared)

VPC Attachments:
- VPC Shared attachment: $36.50/month
- VPC C attachment: $0 (Account C pays)
- VPC D attachment: $0 (Account D pays)
- VPC Ingress attachment: $0 (Account Ingress pays)
- VPC Egress attachment: $0 (Account Egress pays)

Peering:
- Peering attachment (ap-southeast-1 side): $36.50/month

TGW Data Processing (all ap-southeast-1 traffic):

From us-east-1 (cross-region inbound):
- VPC A → Shared: 36 GB × $0.02 = $0.72
- VPC A → VPC C: 390 GB × $0.02 = $7.80
- VPC B → Shared: 75 GB × $0.02 = $1.50

Same region (ap-southeast-1):
- VPC C ↔ Shared: 1.004 TB/day × 30 = 30.12 TB × $0.02/GB = $602.40
- VPC D ↔ Shared: 3.5 TB/day × 30 = 105 TB × $0.02/GB = $2,100.00
- Ingress → VPC C: 4 TB/day × 30 = 120 TB × $0.02/GB = $2,400.00
- Ingress → VPC D: 3 TB/day × 30 = 90 TB × $0.02/GB = $1,800.00
- VPC C → Egress: 10 TB/day × 30 = 300 TB × $0.02/GB = $6,000.00
- VPC D → Egress: 20 TB/day × 30 = 600 TB × $0.02/GB = $12,000.00

TGW Processing Subtotal: $24,912.42/month

VPC Endpoints (2 AZs):
- KMS: 2 endpoints × $0.01/hour × 730 hours = $14.60/month
- S3: Gateway endpoint = $0
- DynamoDB: Gateway endpoint = $0

Account Shared Total: $25,000.02/month

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━


### Account Ingress (VPC Ingress only)

VPC Attachments:
- VPC Ingress attachment to Account Shared's TGW: $36.50/month

Account Ingress Total: $36.50/month

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━


### Account Egress (VPC Egress only)

VPC Attachments:
- VPC Egress attachment to Account Shared's TGW: $36.50/month

Internet Data Transfer Out:
- Total egress: 30 TB/day × 30 = 900 TB/month
- Cost: 900,000 GB × $0.09/GB = $81,000/month

Account Egress Total: $81,036.50/month

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━


## Summary Table

| Account | Role | VPC Attachment | Peering | TGW Processing | Cross-Region Transfer | Internet Egress | VPC Endpoints | Monthly 
Total |
|---------|------|----------------|---------|----------------|----------------------|-----------------|---------------|---------
----------|
| A | TGW Owner + VPC | $36.50 | $36.50 | $16.62 | $10.02 | - | - | $99.64 |
| B | VPC Only | $36.50 | - | - | - | - | - | $36.50 |
| C | VPC Only | $36.50 | - | - | - | - | - | $36.50 |
| D | VPC Only | $36.50 | - | - | - | - | - | $36.50 |
| Shared | TGW Owner + VPC | $36.50 | $36.50 | $24,912.42 | - | - | $14.60 | $25,000.02 |
| Ingress | VPC Only | $36.50 | - | - | - | - | - | $36.50 |
| Egress | VPC Only | $36.50 | - | - | - | $81,000 | - | $81,036.50 |

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━


## Grand Total: $106,282.16/month

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━


## Cost Breakdown by Category

| Category | Total Cost | % of Total |
|----------|------------|------------|
| Internet Egress | $81,000.00 | 76.2% |
| TGW Data Processing | $24,929.04 | 23.5% |
| VPC Attachments | $255.50 | 0.24% |
| Peering Attachments | $73.00 | 0.07% |
| VPC Endpoints | $14.60 | 0.01% |
| Cross-Region Transfer | $10.02 | 0.01% |

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━


## Key Insights

### 1. Cost Distribution
- **Account Egress:** 76.2% of total costs ($81,036.50) - dominated by internet egress
- **Account Shared:** 23.5% of total costs ($25,000.02) - TGW processing for high-volume traffic
- **Other accounts:** <0.1% each ($36.50-$99.64) - minimal infrastructure costs

### 2. TGW Owner Burden
- **Account A:** Pays $16.62 processing + $10.02 cross-region = $26.64 for other accounts' traffic
- **Account Shared:** Pays $24,912.42 processing for other accounts' traffic
- **Chargeback needed:** TGW owners subsidize other accounts significantly

### 3. Attachment Billing Confirmed
- Each VPC owner pays $36.50 for their own attachment
- TGW owners do NOT pay for shared VPC attachments
- Total attachment fees: 7 VPCs × $36.50 = $255.50

### 4. Biggest Cost Drivers
1. Internet egress (900 TB): $81,000/month
2. VPC D ↔ Egress (600 TB): $12,000/month in TGW processing
3. VPC C ↔ Egress (300 TB): $6,000/month in TGW processing
4. VPC D ↔ Shared (105 TB): $2,100/month in TGW processing

### 5. Optimization Opportunities
- **Direct Connect for egress:** Could save ~$63,000/month
- **VPC Peering for C/D ↔ Shared:** Could save ~$2,700/month
- **Regional data optimization:** Keep data where it's consumed
- **CloudFront for cacheable content:** Could save ~$4,500/month

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━


## Key Observations

### Cost Distribution

1. Account Shared bears 24% of total costs ($25,146) due to:
   - Owning the high-traffic ap-southeast-1 TGW
   - Processing 1,050+ TB/month of data
   - 5 VPC attachments + peering

2. Account Egress bears 76% of total costs ($81,036) due to:
   - Internet egress charges dominate (900 TB/month)
   - Only pays $36.50 for TGW attachment

3. Accounts B, C, D, Ingress pay minimal costs ($36.50 each)
   - Only VPC attachment fees
   - TGW processing paid by TGW owners

4. Account A has moderate costs ($99.64)
   - Lower traffic volume in us-east-1
   - Cross-region transfer costs

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━


## 5. Optimization & Best Practices

### Cost Optimization

1. Chargeback Model for TGW Owners
- Account Shared pays $24,912 in processing fees for other accounts' traffic
- Implement CloudWatch-based chargeback:
  - Monitor BytesIn/BytesOut per attachment
  - Allocate costs to actual VPC owners
  - Use AWS Cost Allocation Tags

2. VPC Peering for High-Volume Same-Region Traffic
- VPC C ↔ Shared: 1.004 TB/day = $602.40/month in TGW fees
- VPC D ↔ Shared: 3.5 TB/day = $2,100/month in TGW fees
- **VPC Peering alternative:** Only cross-AZ charges (~$0.01/GB) = ~$1,050/month savings
- **Recommendation:** Use VPC Peering for C/D ↔ Shared, keep TGW for cross-region/multi-VPC routing

3. Optimize Internet Egress
- 900 TB/month = $81,000 is the largest cost
- **CloudFront:** If serving web content, can reduce to ~$76,500 (10% savings)
- **S3 Transfer Acceleration:** For uploads, may be cheaper than routing through TGW
- **Direct Connect:** If sustained high volume, DX can reduce to $0.02/GB = $18,000/month (78% savings)
- **Regional optimization:** Keep data in region where it's consumed

4. Right-Size VPC Endpoints
- Currently: 2 KMS endpoints = $14.60/month
- **Audit usage:** If low volume, consider using TGW to route to single endpoint
- **S3/DynamoDB Gateway endpoints:** Already optimal (free)

5. TGW Route Table Optimization
- Use separate route tables to prevent unnecessary routing
- Isolate Ingress/Egress traffic from internal VPC traffic
- Reduces data processing for traffic that doesn't need full mesh connectivity

### Architecture Best Practices

6. Implement Network Segmentation
Route Table 1: Production (VPC C, D)
Route Table 2: Shared Services (VPC Shared)
Route Table 3: Edge (Ingress, Egress)
Route Table 4: Cross-Region (Peering)


7. Enable Monitoring & Logging
- **TGW Flow Logs:** Send to S3 for cost analysis and security
- **VPC Flow Logs:** On all VPCs
- **CloudWatch Alarms:**
  - Unusual traffic spikes (>20% baseline)
  - Attachment state changes
  - Peering connection health

8. Use AWS Resource Access Manager (RAM) Properly
- Already doing this correctly
- Add resource tags for cost allocation
- Set up RAM sharing with specific OUs, not individual accounts

9. Implement AWS Network Firewall
- In VPC Egress for centralized inspection
- In VPC Ingress for threat prevention
- Cost: ~$0.065/GB + $0.395/hour per AZ = ~$600/month + $58,500 for 900TB
- Consider for compliance requirements

10. DNS Strategy
- Deploy Route 53 Resolver endpoints in VPC Shared
- Centralized DNS management
- Cost: $0.125/hour per endpoint × 2 AZs = $182.50/month

11. High Availability
- TGW attachments already span multiple AZs (automatic)
- Ensure applications in VPCs are multi-AZ
- Test failover scenarios

12. Security Best Practices
- **Least privilege routing:** Use TGW route tables to restrict VPC-to-VPC communication
- **Security Groups:** Reference security groups across VPCs using TGW
- **NACLs:** Defense in depth at subnet level
- **AWS Network Access Analyzer:** Validate intended network paths

### Operational Excellence

13. Infrastructure as Code
Terraform/CloudFormation for:
- TGW configuration
- Route tables
- RAM shares
- VPC attachments


14. Tagging Strategy
Environment: Production/Dev
CostCenter: <department>
Owner: <team>
Application: <app-name>


15. Regular Reviews
- **Monthly:** Review CloudWatch metrics for traffic patterns
- **Quarterly:** Evaluate VPC Peering vs TGW for high-volume pairs
- **Annually:** Architecture review for new AWS services

16. Disaster Recovery
- Document TGW configuration
- Automate TGW recreation via IaC
- Test cross-region failover scenarios

17. Consider AWS Transit Gateway Network Manager
- Global network visualization
- Centralized monitoring across regions
- Route analysis and troubleshooting
- Cost: $2.50/device/month (if using SD-WAN integration)

### Immediate Action Items

Priority 1 (High Impact):
1. Implement chargeback model for Account Shared's TGW costs
2. Evaluate Direct Connect for Egress traffic (potential $63K/month savings)
3. Assess VPC Peering for VPC C/D ↔ Shared (potential $2.7K/month savings)

Priority 2 (Medium Impact):
4. Enable TGW Flow Logs for cost analysis
5. Implement separate TGW route tables for segmentation
6. Set up CloudWatch alarms for traffic anomalies

Priority 3 (Best Practices):
7. Deploy Network Firewall in Egress VPC
8. Implement Route 53 Resolver in Shared VPC
9. Document and automate with IaC

The most significant optimization opportunity is the internet egress cost ($81K/month). Evaluating Direct Connect or regional 
optimization could save $50K+/month.