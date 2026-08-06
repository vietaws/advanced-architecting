# Hybrid DNS Demo Plan — 5 Hours

## Domain Names

| Environment | Domain | Authority | Example Records |
|---|---|---|---|
| AWS Cloud (VPC A) | `cloud.viet.vn` | Route 53 Private Hosted Zone | `app.cloud.viet.vn`, `db.cloud.viet.vn` |
| On-Premises (VPC OP) | `op.viet.vn` | BIND on EC2 | `app.op.viet.vn`, `db.op.viet.vn`, `dns.op.viet.vn` |

> `cloud.viet.vn` is treated as a **private** hosted zone throughout this demo — it resolves only inside the VPCs, not on the public internet. In a real environment this would be a domain you own, with a separate public hosted zone for external traffic.

---

## Architecture

```
┌─────────────────────────────────────────────────────┐
│              VPC A — Cloud (10.1.0.0/16)            │
│                                                     │
│  ┌──────────────────┐   ┌───────────────────────┐   │
│  │ Public Subnet A  │   │ Private Subnet A2     │   │
│  │ 10.1.0.0/24      │   │ 10.1.2.0/24           │   │
│  │                  │   │                       │   │
│  │ EC2-Cloud        │   │ (Resolver IPs only)   │   │
│  │ 10.1.0.40        │   │                       │   │
│  │ app.cloud.viet.vn│   │                       │   │
│  └──────────────────┘   └───────────────────────┘   │
│                                                     │
│  ┌──────────────────┐   ┌───────────────────────┐   │
│  │ Private Subnet A │   │ Private Subnet A2     │   │
│  │ 10.1.1.0/24      │   │ 10.1.2.0/24           │   │
│  │                  │   │                       │   │
│  │ Inbound EP       │   │ Inbound EP            │   │
│  │ 10.1.1.10        │   │ 10.1.2.10             │   │
│  │ Outbound EP      │   │ Outbound EP           │   │
│  │ 10.1.1.11        │   │ 10.1.2.11             │   │
│  └──────────────────┘   └───────────────────────┘   │
│                                                     │
│  Route 53 Private Hosted Zone: cloud.viet.vn        │
│  S3 Gateway Endpoint                                │
└─────────────────────────┬───────────────────────────┘
                          │ VPC Peering
                          │ (real world: VPN / Direct Connect)
┌─────────────────────────┴───────────────────────────┐
│           VPC OP — On-Premises (10.2.0.0/16)        │
│                                                     │
│  ┌──────────────────────────────────────────────┐   │
│  │ Public Subnet OP — 10.2.1.0/24               │   │
│  │                                              │   │
│  │ DNS Server (BIND)     App Server             │   │
│  │ dns.op.viet.vn        app.op.viet.vn         │   │
│  │ 10.2.1.10             10.2.1.20              │   │
│  │                                              │   │
│  │                       DB Server              │   │
│  │                       db.op.viet.vn          │   │
│  │                       10.2.1.30              │   │
│  └──────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────┘
```

---

## Agenda

| Level | Scenario | Key Activities | Guide |
|------|----------|----------------|-------|
| **0** | Foundation Setup | Deploy VPCs, EC2s, VPC Peering, BIND, S3 |  |
| **1** | Scenario 1: All DNS on On-Premises | DHCP override, BIND authoritative for both domains | `1-scenario-all-dns-op.md` |
| **2** | Scenario 2: All DNS on AWS | Route 53 PHZ for both domains, Inbound Endpoint, Query Logging | `2-scenario-all-dns-aws.md` |
| **3** | Scenario 3: Split DNS | Outbound Endpoint + Resolver Rule, each side owns its zone | `3-scenario-split-dns.md` §Split DNS |
| **4** | Advanced Features + Wrap-up | DNS Firewall, CNAME/Alias, RAM sharing, cost comparison | `5-comparison.md` |

---

## Foundation Setup

**Goal:** Get base infrastructure running. All later scenarios build on this.

### What to deploy

| Resource | Details |
|---|---|
| VPC A | `10.1.0.0/16`, DNS hostnames + support enabled |
| Subnet A (AZ-a) | `10.1.1.0/24` |
| Subnet A2 (AZ-b) | `10.1.2.0/24` — needed for Resolver HA |
| VPC OP | `10.2.0.0/16` |
| Subnet OP | `10.2.1.0/24` |
| VPC Peering | VPC A ↔ VPC OP, routes added both sides |
| EC2-Cloud | VPC A, `10.1.0.40`, private only, no public IP |
| DNS Server (BIND) | VPC OP, `10.2.1.10`, BIND installed and running |
| App Server | VPC OP, `10.2.1.20` |
| S3 Bucket | `ap-southeast-1`, private |
| S3 Gateway Endpoint | VPC A route table |


---

## Scenario 1: All DNS on On-Premises

**Scenario:** On-prem team controls everything. BIND is authoritative for both `op.viet.vn` and `cloud.viet.vn`. VPC A is configured to use BIND as its DNS server via custom DHCP options.

**Key demo moments:**
1. `dig app.op.viet.vn` from EC2-Cloud → BIND answers
2. `dig app.cloud.viet.vn` from App Server → BIND answers
3. `aws s3 ls` from EC2-Cloud → works (AWS service DNS forwarded correctly)
4. Tail BIND query log → all queries visible in one place
5. Disable BIND → both VPCs lose DNS (illustrate single point of failure)

**Cost:** ~$32/month

**Full guide:** `1-scenario-all-dns-op.md`

---

## Scenario 2: All DNS on AWS

**Scenario:** AWS manages DNS for both environments. Route 53 has two PHZs: `cloud.viet.vn` and `op.viet.vn`. BIND becomes a pure forwarder.

**Key demo moments:**
1. Create Route 53 PHZ for `cloud.viet.vn` + associate with VPC A and VPC OP
2. Create Route 53 PHZ for `op.viet.vn` + add records for on-prem hosts
3. Deploy Inbound Resolver Endpoint (2 IPs for HA)
4. Reconfigure BIND to forward everything to `10.1.1.10` and `10.1.2.10`
5. `dig app.cloud.viet.vn` from EC2-Cloud → VPC DNS resolves directly (no BIND hop)
6. `dig app.op.viet.vn` from App Server → BIND → Inbound Endpoint → PHZ
7. Enable Resolver Query Logging → show CloudWatch Logs with live traces
8. Disable BIND → cloud-to-cloud DNS still works; on-prem-to-cloud DNS still works

**Cost:** ~$182/month (inbound endpoint only)

**Full guide:** `2-scenario-all-dns-aws.md`

---

## Scenario 3: Split DNS

**Scenario:** Best of both. Route 53 owns `cloud.viet.vn`. BIND owns `op.viet.vn`. They forward cross-domain queries to each other via Resolver endpoints.

**Key demo moments:**
1. Deploy Outbound Resolver Endpoint + Resolver Rule for `op.viet.vn` → BIND
2. BIND keeps `op.viet.vn` zone, adds forwarder for `cloud.viet.vn` → Inbound Endpoint
3. `dig app.cloud.viet.vn` from EC2-Cloud → resolves locally in VPC, never touches BIND
4. `dig app.op.viet.vn` from EC2-Cloud → Outbound Endpoint → BIND → answer
5. `dig app.op.viet.vn` from App Server → goes straight to BIND, no AWS hop
6. Kill BIND → cloud DNS still works, only `op.viet.vn` queries fail
7. Restart BIND → automatic recovery

**Cost:** ~$365/month (inbound + outbound endpoints)

**Full guide:** `3-scenario-split-dns.md`

---

## Advanced Features + Wrap-up

### DNS Firewall
- Create a rule group blocking `malware-test.op.viet.vn`
- Attach to VPC A
- Show blocked response in CloudWatch Logs

### CNAME and Alias Records in PHZ
- Add `api.cloud.viet.vn CNAME app.cloud.viet.vn`
- Show alias behavior vs CNAME
- Contrast with public hosted zone behavior

### Resolver Rule Sharing via RAM
- Show how `op.viet.vn` Resolver Rule can be shared to other AWS accounts
- Use case: multiple accounts in an AWS Organization all resolving `op.viet.vn`

### Cost Comparison
- Walk through all 3 scenarios side by side
- Map cost to real-world use cases
- Show migration roadmap

### Wrap-up Q&A 

**Full guide:** `5-comparison.md`

---

## IP Address Reference

| Host | VPC | IP | Hostname |
|------|----|-----|----------|
| EC2-Cloud | VPC A | `10.1.0.40` | `app.cloud.viet.vn` |
| Inbound Resolver (AZ-a) | VPC A | `10.1.1.10` | — |
| Inbound Resolver (AZ-b) | VPC A | `10.1.2.10` | — |
| Outbound Resolver (AZ-a) | VPC A | `10.1.1.11` | — |
| Outbound Resolver (AZ-b) | VPC A | `10.1.2.11` | — |
| DNS Server (BIND) | VPC OP | `10.2.1.10` | `dns.op.viet.vn` |
| App Server | VPC OP | `10.2.1.20` | `app.op.viet.vn` |
| DB Server (simulated) | VPC OP | `10.2.1.30` | `db.op.viet.vn` |
| VPC A DNS Resolver | VPC A | `10.1.0.2` | AmazonProvidedDNS |
| VPC OP DNS Resolver | VPC OP | `10.2.0.2` | AmazonProvidedDNS |

---