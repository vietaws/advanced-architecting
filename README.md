# Hybrid DNS Demo — Amazon Route 53 & On-Premises

A hands-on 5-hour demo covering hybrid DNS resolution between AWS (Amazon Route 53) and an on-premises environment simulated via VPC Peering.

---

## What This Demo Covers

| Route 53 / DNS Feature | Demonstrated In |
|---|---|
| Private Hosted Zone (PHZ) | Scenarios 1, 2, 3 |
| PHZ — multi-VPC association | Scenario 2 |
| PHZ — CNAME and Alias records | Scenarios 2, 3, Advanced |
| Inbound Resolver Endpoint | Scenarios 2, 3 |
| Outbound Resolver Endpoint | Scenario 3 |
| Resolver Rules (FORWARD type) | Scenario 3 |
| Resolver Query Logging → CloudWatch | Scenario 2 |
| DNS Firewall + managed domain lists | Advanced Features |
| Resolver Rule sharing via AWS RAM | Advanced Features |
| Custom DHCP Options | Scenario 1 |
| BIND conditional forwarding | Scenarios 1, 3 |
| S3 Gateway Endpoint DNS | Foundation |

---

## Architecture

```
┌─────────────────────────────────────────────────────┐
│              VPC A — Cloud (10.1.0.0/16)            │
│                                                     │
│  Subnet 10.1.1.0/24 (AZ-a)                         │
│  ┌──────────────────────────────────────────────┐   │
│  │  EC2-Cloud          10.1.1.50                │   │
│  │  app.cloud.viet.vn                        │   │
│  │                                              │   │
│  │  Inbound Resolver   10.1.1.10  (Scenarios 2, 3)    │   │
│  │  Outbound Resolver  10.1.1.11  (Scenario 3)     │   │
│  └──────────────────────────────────────────────┘   │
│                                                     │
│  Subnet 10.1.2.0/24 (AZ-b) — Resolver HA           │
│  ┌──────────────────────────────────────────────┐   │
│  │  Inbound Resolver   10.1.2.10  (Scenarios 2, 3)    │   │
│  │  Outbound Resolver  10.1.2.11  (Scenario 3)     │   │
│  └──────────────────────────────────────────────┘   │
│                                                     │
│  Route 53 PHZ: cloud.viet.vn                     │
│  S3 Gateway Endpoint                                │
└──────────────────────┬──────────────────────────────┘
                       │ VPC Peering
                       │ (real world: VPN / Direct Connect)
┌──────────────────────┴──────────────────────────────┐
│           VPC OP — On-Premises (10.2.0.0/16)        │
│                                                     │
│  Subnet 10.2.1.0/24                                 │
│  ┌──────────────────────────────────────────────┐   │
│  │  DNS Server (BIND)  10.2.1.10                │   │
│  │  dns.op.viet.vn                              │   │
│  │                                              │   │
│  │  App Server         10.2.1.20                │   │
│  │  app.op.viet.vn                              │   │
│  │                                              │   │
│  │  DB Server (MySQL)  10.2.1.30                │   │
│  │  db.op.viet.vn                               │   │
│  └──────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────┘
```

### Domain Names

| Domain | Owner | Records |
|--------|-------|---------|
| `cloud.viet.vn` | Route 53 Private Hosted Zone | `app.cloud.viet.vn` → `10.1.1.50` |
| `op.viet.vn` | BIND on DNS Server | `app.op.viet.vn` → `10.2.1.20`, `db.op.viet.vn` → `10.2.1.30` |

---

## Three Scenarios

The same base infrastructure supports three DNS architectures, demonstrated in sequence:

### Scenario 1 — All DNS on On-Premises
BIND is authoritative for both `op.viet.vn` and `cloud.viet.vn`. VPC A uses custom DHCP options to point at BIND. AWS service queries (S3, EC2 APIs) are conditionally forwarded back to `10.1.0.2`.

- **Cost:** ~$0/month Route 53 (no resolver endpoints)
- **Best for:** Early cloud adoption, on-prem team retains full control

### Scenario 2 — All DNS on AWS
Route 53 hosts two PHZs: `cloud.viet.vn` and `op.viet.vn`. BIND becomes a pure forwarder to the Inbound Resolver Endpoint. Resolver Query Logging provides full visibility in CloudWatch.

- **Cost:** ~$184/month Route 53 (inbound endpoint only)
- **Best for:** Cloud-first organisations, centralised DNS visibility

### Scenario 3 — Split DNS
Route 53 owns `cloud.viet.vn`. BIND owns `op.viet.vn`. Cross-domain queries are routed via Resolver Endpoints. Each environment resolves its own domain locally with no round-trip.

- **Cost:** ~$438/month Route 53 (inbound + outbound endpoints + rule)
- **Best for:** Long-term hybrid, best performance, smallest blast radius

---

## Repository Structure

```
.
├── README.md
├── app.js                          # Express app for App Server (copy to /opt/app/ on instance)
├── scripts/                        # EC2 user-data scripts
│   ├── userdata-dns-server.sh      # BIND setup (10.2.1.10)
│   ├── userdata-app-server.sh      # On-prem app server (10.2.1.20)
│   ├── userdata-db-server.sh       # On-prem DB server — MariaDB (10.2.1.30)
│   └── userdata-ec2-cloud.sh       # Cloud app server (10.1.1.50)
└── guides/                         # Step-by-step demo guides
    ├── 0-demo-plan.md              # 5-hour agenda, IP reference, pre-flight checklist
    ├── 1-problem.md                # Problem statement — why hybrid DNS is needed
    ├── 3-scenario-split-dns.md  # Foundation setup + Scenario 3: Split DNS
    ├── 2-scenario-all-dns-aws.md      # Scenario 2: All DNS on AWS
    ├── 1-scenario-all-dns-op.md         # Scenario 1: All DNS on On-Premises
    └── 5-comparison.md             # Advanced Features + cost comparison
```

---

## Prerequisites

- AWS account with permissions for: EC2, VPC, Route53, Route53Resolver, S3, Logs, RAM
- AWS CLI configured (`aws configure`)
- `jq` installed
- An EC2 key pair in `ap-southeast-1`
- SSM Session Manager (recommended for SSH-less access to private EC2s)
  — attach `AmazonSSMManagedInstanceCore` IAM policy to the EC2 instance profile

---

## Quick Start

### 1. Deploy base infrastructure

Launch each EC2 instance manually in the AWS Console or via CLI, passing the corresponding script from `scripts/` as EC2 user-data:

| Instance | IP | User-data script |
|----------|----|-----------------|
| DNS Server | `10.2.1.10` (VPC OP) | `scripts/userdata-dns-server.sh` |
| App Server | `10.2.1.20` (VPC OP) | `scripts/userdata-app-server.sh` |
| DB Server | `10.2.1.30` (VPC OP) | `scripts/userdata-db-server.sh` |
| EC2-Cloud | `10.1.1.50` (VPC A) | `scripts/userdata-ec2-cloud.sh` |

Follow `guides/3-scenario-split-dns.md` (Part 1) for the full step-by-step CLI commands to create VPCs, subnets, peering, security groups, and the S3 gateway endpoint.

> User-data scripts run in the background on each EC2 after boot. Allow 3–5 min for BIND, MariaDB, and the HTTP servers to be ready.

### 2. Follow the demo guides in order

| Hour | Guide |
|------|-------|
| 1 | Infrastructure deployed above |
| 2 | `guides/1-scenario-all-dns-op.md` |
| 3 | `guides/2-scenario-all-dns-aws.md` |
| 4 | `guides/3-scenario-split-dns.md` (Part 2) |
| 5 | `guides/5-comparison.md` |

### 3. Tear down

Delete all resources in reverse order via the AWS Console or CLI:
1. Route 53 Resolver Endpoints, Rules, PHZs, DNS Firewall rule groups, CloudWatch log groups
2. EC2 instances
3. S3 bucket
4. VPC Peering connection
5. Subnets, security groups, VPCs

---

## Demo Testing Commands

Each EC2 has a `dns-test` helper pre-installed. Connect via SSM or SSH, then:

```bash
# On any EC2 — quick DNS resolution check
dns-test

# On EC2-Cloud only — test MySQL across the hybrid boundary
db-test
```

Manual `dig` tests:

```bash
# Cloud domain
dig app.cloud.viet.vn

# On-prem domains
dig app.op.viet.vn
dig db.op.viet.vn

# CNAME record
dig api.cloud.viet.vn

# AWS service (should always resolve)
dig s3.ap-southeast-1.amazonaws.com

# Verify which DNS server answered
dig app.op.viet.vn +noall +answer +comments | grep SERVER
```

---

## Cost Summary

| Scenario | Route 53 / month | Notes |
|----------|:----------------:|-------|
| All On-Prem (Scenario 1) | $0 | No resolver endpoints |
| All AWS (Scenario 2) | ~$184 | Inbound endpoint (2 IPs HA) |
| Split DNS (Scenario 3) | ~$438 | Inbound + Outbound endpoints + 1 rule |

The dominant cost in all cases is the Resolver Endpoint: **$0.125/hour per IP address**. For a demo/dev environment, reduce to 1 IP per endpoint (single AZ) to cut costs in half.

---

## Key Concepts Recap

**Inbound Resolver Endpoint** — a pair of IP addresses in your VPC that on-premises DNS servers can forward queries to. Queries arrive at these IPs and are answered by Route 53 Private Hosted Zones.

**Outbound Resolver Endpoint** — a pair of IP addresses in your VPC that Route 53 uses as a source to send forwarded queries outbound. Used together with Resolver Rules.

**Resolver Rule** — tells Route 53: "for domain X, send queries via the Outbound Endpoint to this target IP." Without a rule, Route 53 only resolves domains in its own hosted zones.

**Private Hosted Zone** — a Route 53 hosted zone that resolves only from within associated VPCs. The domain name does not need to be publicly registered.

**Split DNS** — a pattern where the same parent namespace (e.g. `op.viet.vn`) is split between two authorities: Route 53 owns `cloud.viet.vn`, BIND owns `op.viet.vn`. Each side resolves its own sub-domain locally and forwards the other direction via Resolver Endpoints.
