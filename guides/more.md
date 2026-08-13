# Advanced Features

## DNS Firewall
- Create a rule group blocking `malware-test.op.viet.vn`
- Attach to VPC A
- Show blocked response in CloudWatch Logs

## CNAME and Alias Records in PHZ
- Add `api.cloud.viet.vn CNAME app.cloud.viet.vn`
- Show alias behavior vs CNAME
- Contrast with public hosted zone behavior

## Resolver Rule Sharing via RAM
- Show how `op.viet.vn` Resolver Rule can be shared to other AWS accounts
- Use case: multiple accounts in an AWS Organization all resolving `op.viet.vn`

---

# Advanced Features, Cost Comparison & Decision Framework

## Overview

This guide has four parts:
1. **DNS Firewall** — block malicious/unwanted domains at the resolver level
2. **CNAME and Alias records** in Route 53 Private Hosted Zones
3. **Resolver Rule sharing via RAM** — extend a single Outbound Endpoint to multiple AWS accounts
4. **Cost comparison + decision framework** across all three scenarios

---

# Part 1 — DNS Firewall

Route 53 Resolver DNS Firewall intercepts DNS queries leaving VPC A and blocks or allows them based on rule groups. It is the DNS-layer equivalent of a security group.

## When to Use

- Block known malicious domains (using AWS Managed Domain Lists)
- Prevent data exfiltration via DNS tunneling
- Enforce egress domain allowlisting for sensitive VPCs

## Step 1 — Create a Rule Group

```bash
FW_RULE_GROUP=$(aws route53resolver create-firewall-rule-group \
  --name "HybridDNS-Firewall" \
  --region ap-southeast-1 \
  --query 'FirewallRuleGroup.Id' --output text)

echo "Firewall Rule Group: $FW_RULE_GROUP"
```

## Step 2 — Create a Domain List to Block

```bash
FW_DOMAIN_LIST=$(aws route53resolver create-firewall-domain-list \
  --name "BlockList-Demo" \
  --region ap-southeast-1 \
  --query 'FirewallDomainList.Id' --output text)

# Add test domains to block
aws route53resolver update-firewall-domains \
  --firewall-domain-list-id $FW_DOMAIN_LIST \
  --operation ADD \
  --domains "malware-test.op.viet.vn" "exfil.badactor.com" \
  --region ap-southeast-1
```

## Step 3 — Create a Firewall Rule

```bash
aws route53resolver create-firewall-rule \
  --firewall-rule-group-id $FW_RULE_GROUP \
  --firewall-domain-list-id $FW_DOMAIN_LIST \
  --priority 100 \
  --action BLOCK \
  --block-response NXDOMAIN \
  --name "Block-Malicious-Domains" \
  --region ap-southeast-1
```

## Step 4 — Associate Rule Group with VPC A

```bash
aws route53resolver associate-firewall-rule-group \
  --firewall-rule-group-id $FW_RULE_GROUP \
  --vpc-id $VPC_A_ID \
  --priority 200 \
  --name "HybridDNS-Firewall-VPC-A" \
  --region ap-southeast-1
```

## Demo Verification

```bash
# From EC2-Cloud (10.1.0.40)

# Blocked domain returns NXDOMAIN
dig malware-test.op.viet.vn
# Expected: NXDOMAIN (blocked by firewall)

dig exfil.badactor.com
# Expected: NXDOMAIN

# Legitimate domains still resolve
dig app.cloud.viet.vn
# Expected: 10.1.0.40

# Check CloudWatch Logs for firewall block events
# Filter: { $.firewall_rule_action = "BLOCK" }
```

## AWS Managed Domain Lists

AWS provides regularly updated domain lists you can use instead of maintaining your own:

```bash
# List available managed domain lists
aws route53resolver list-firewall-managed-domain-lists \
  --region ap-southeast-1

# Notable lists:
# AWSManagedDomainsMalwareDomainList
# AWSManagedDomainsAggregateThreatList
# AWSManagedDomainsAmazonGuardDutyThreatList
```

---

# Part 2 — CNAME and Alias Records in PHZ

## CNAME Records

A CNAME in a Private Hosted Zone works the same as in a public zone — it points one name to another. Useful for abstracting service endpoints.

```bash
# CNAME already created in the All-AWS or Split DNS scenario:
# api.cloud.viet.vn → app.cloud.viet.vn → 10.1.0.40

dig api.cloud.viet.vn
# Returns: CNAME api.cloud.viet.vn → app.cloud.viet.vn, then A 10.1.0.40
```

**Limitation:** You cannot use a CNAME at the zone apex (`cloud.viet.vn` itself). Use an Alias record there instead.

## Alias Records

Alias records in Route 53 are Route 53-specific. They allow a name to point to another AWS resource (ALB, CloudFront, another Route 53 record) with zero TTL and no extra DNS lookup charge.

In a Private Hosted Zone, Alias records are commonly used to point to:
- Internal Application Load Balancers
- VPC Interface Endpoints (PrivateLink)
- Another record in the same hosted zone

```bash
# Example: alias zone apex to app record
cat > /tmp/alias-record.json << EOF
{
  "Changes": [{
    "Action": "CREATE",
    "ResourceRecordSet": {
      "Name": "cloud.viet.vn",
      "Type": "A",
      "AliasTarget": {
        "HostedZoneId": "$PHZ_CLOUD",
        "DNSName": "app.cloud.viet.vn",
        "EvaluateTargetHealth": false
      }
    }
  }]
}
EOF

aws route53 change-resource-record-sets \
  --hosted-zone-id $PHZ_CLOUD \
  --change-batch file:///tmp/alias-record.json

# Test zone apex resolution
dig cloud.viet.vn
# Expected: 10.1.0.40 (resolves through alias chain, no CNAME shown)
```

**Key difference to show:** `dig api.cloud.viet.vn` shows the CNAME in the answer section. `dig cloud.viet.vn` with an Alias record returns only the A record — the alias is transparent at the DNS level.

---

# Part 3 — Resolver Rule Sharing via AWS RAM

## The Problem

In an AWS Organization with many accounts, each account's VPC that needs to resolve `op.viet.vn` would need its own Outbound Resolver Endpoint and Resolver Rule. That is expensive and operationally complex.

## The Solution

Share the Resolver Rule (and its associated Outbound Endpoint) from a central networking account to all other accounts via **AWS Resource Access Manager (RAM)**.

```
Central Networking Account
  └── Outbound Resolver Endpoint
  └── Resolver Rule: op.viet.vn → BIND (10.2.1.10)
        └── Shared via RAM to Org / OUs / specific accounts

Dev Account VPC A     → associates shared rule → resolves op.viet.vn
Prod Account VPC B    → associates shared rule → resolves op.viet.vn
Data Account VPC C    → associates shared rule → resolves op.viet.vn
```

## Step 1 — Share the Resolver Rule

```bash
# Get your AWS Organization ID
ORG_ID=$(aws organizations describe-organization \
  --query 'Organization.Id' --output text)

# Share the rule with the entire organization
aws ram create-resource-share \
  --name "SharedResolverRule-corp-local" \
  --resource-arns "arn:aws:route53resolver:ap-southeast-1:$(aws sts get-caller-identity --query Account --output text):resolver-rule/$RULE_ID" \
  --principals "arn:aws:organizations::$(aws sts get-caller-identity --query Account --output text):organization/$ORG_ID" \
  --region ap-southeast-1
```

## Step 2 — Associate Rule in Target Account

In each target account, accept the RAM share and associate the rule with their VPC:

```bash
# In target account:
# 1. Accept the RAM resource share invitation
aws ram accept-resource-share-invitation \
  --resource-share-invitation-arn <invitation-arn> \
  --region ap-southeast-1

# 2. Associate the shared rule with target VPC
aws route53resolver associate-resolver-rule \
  --resolver-rule-id $RULE_ID \
  --vpc-id <target-vpc-id> \
  --region ap-southeast-1
```

**Talking point:** One Outbound Endpoint in the central account handles `op.viet.vn` resolution for the entire organization. This is the standard pattern in AWS Landing Zone / Control Tower environments.

---

# Part 4 — Cost Comparison & Decision Framework

## Monthly Cost Comparison

| Component | Scenario 1: All AWS | Scenario 2: All On-Prem | Scenario 3: Split DNS |
|-----------|:-------------------:|:-----------------------:|:---------------------:|
| Inbound Resolver (2 IPs) | $182.50 | — | $182.50 |
| Outbound Resolver (2 IPs) | — | — | $182.50 |
| Resolver Rule(s) | — | — | $73.00 |
| PHZ `cloud.viet.vn` | $0.50 | — | $0.50 |
| PHZ `op.viet.vn` | $0.50 | — | — |
| DNS queries (1M est.) | $0.40 | — | $0.40 |
| **Route 53 Total** | **~$184/mo** | **$0/mo** | **~$438/mo** |

> EC2 Instance cost (t4g.micro) is part of base infrastructure in all scenarios: ~$6.13/month.

## Performance Comparison

| Query | Scenario 1: All AWS | Scenario 2: All On-Prem | Scenario 3: Split DNS |
|-------|:-------------------:|:-----------------------:|:---------------------:|
| `app.cloud.viet.vn` from EC2-Cloud | ⚡ <1ms (local VPC DNS) | ~5ms (VPC Peering to BIND) | ⚡ <1ms (local VPC DNS) |
| `app.op.viet.vn` from EC2-Cloud | ⚡ <1ms (PHZ in Route 53) | ~5ms (VPC Peering to BIND) | ~5ms (Outbound EP → BIND) |
| `app.cloud.viet.vn` from App Server | ~5ms (BIND → Inbound EP) | ~2ms (local BIND) | ~5ms (BIND → Inbound EP) |
| `app.op.viet.vn` from App Server | ~5ms (BIND → Inbound EP) | ⚡ <2ms (local BIND) | ⚡ <2ms (local BIND) |

## Resilience Comparison

| Failure | Scenario 1: All AWS | Scenario 2: All On-Prem | Scenario 3: Split DNS |
|---------|:-------------------:|:-----------------------:|:---------------------:|
| BIND goes down | On-prem VMs lose DNS | **Both environments** lose DNS | Only `op.viet.vn` fails |
| VPC Peering breaks | On-prem VMs lose DNS | **Both environments** lose DNS | Only cross-domain fails |
| Route 53 outage | **Both environments** affected | No impact | `cloud.viet.vn` affected |
| AWS region down | **Both environments** affected | On-prem continues | `cloud.viet.vn` affected |

## Decision Framework

### Choose Scenario 1 (All DNS on On-Premises) when:
- Early cloud adoption — most workloads still on-prem
- On-prem DNS team wants to retain full control
- Compliance or data sovereignty requires on-prem DNS authority
- You want to minimise AWS costs during a pilot phase
- Existing on-prem DNS infrastructure is already highly available

### Choose Scenario 2 (All DNS on AWS) when:
- Cloud workloads are dominant (>70% in AWS)
- You want centralised visibility via CloudWatch Logs
- On-prem DNS team is being decommissioned or is not available
- You need AWS-native service discovery (ECS, EKS)
- Compliance requires DNS audit logs in AWS


### Choose Scenario 3 (Split DNS) when:
- Long-term hybrid strategy — no plans to fully move either way
- Performance is critical in both environments
- You want blast radius isolation (BIND failure shouldn't affect cloud)
- Multiple AWS accounts need to resolve on-prem domains (use RAM sharing)
- Your organisation has separate cloud and infrastructure teams

## Migration Roadmap

```
Year 0-1: Scenario 1 (All On-Prem)
  └── Minimal change, leverage existing BIND
  └── Add Route 53 PHZ as a read-only mirror (optional)

Year 1-2: Scenario 3 (Split DNS)
  └── Add Resolver Endpoints as cloud footprint grows
  └── Route 53 owns cloud.viet.vn, BIND owns op.viet.vn
  └── Implement DNS Firewall for cloud egress control

Year 3+: Scenario 2 (All AWS) or stay at Scenario 3
  └── Move to All-AWS only if on-prem is being decommissioned
  └── Split DNS remains the preferred pattern for mature hybrid
```

---

## Key Takeaways

1. **Route 53 Private Hosted Zones** resolve only from within associated VPCs. On-premises servers cannot reach them directly — that is what the Inbound Resolver Endpoint solves.

2. **Inbound Endpoint** = a door for on-premises queries to enter Route 53. **Outbound Endpoint + Rule** = a door for VPC queries to exit to on-premises DNS.

3. **Split DNS** gives the best performance and blast-radius isolation for long-term hybrid architectures. It is the most common pattern in large enterprises.

4. **DNS Firewall** adds a security layer at no extra infrastructure cost — it hooks into the same Resolver infrastructure already deployed.

5. **Cost is dominated by Resolver Endpoints** ($182.50/month per endpoint for 2 IPs). Evaluate whether both directions truly need HA, especially in dev/test environments.
