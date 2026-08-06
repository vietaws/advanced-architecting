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
Will be updated by image...

```

---

## Foundation Setup

**Goal:** Get base infrastructure running. All later scenarios build on this.

| Resource | Details |
|---|---|
| VPC A | `10.1.0.0/16`, DNS hostnames + support enabled |
| Subnet A (AZ-a) | `10.1.1.0/24` |
| Subnet A2 (AZ-b) | `10.1.2.0/24` — needed for Resolver HA |
| VPC OP | `10.2.0.0/16` |
| Subnet OP | `10.2.1.0/24` |
| VPC Peering | VPC A ↔ VPC OP, routes added both sides |
| EC2-Cloud | VPC A, `10.1.0.40`, private only, no public IP |
| DB-Cloud | VPC A, `10.1.0.50`, private only, no public IP |
| DNS Server (BIND) | VPC OP, `10.2.1.10`, BIND installed and running |
| App Server | VPC OP, `10.2.1.20` |
| Inbound Resolver Ep | VPC A, `10.1.1.10` and `10.1.2.10` |
| Outbound Resolver Ep | VPC A, `10.1.1.11` and `10.1.2.11` |


---

## Scenario 1: All DNS on On-Premises

**Scenario:** On-prem team controls everything. BIND is authoritative for both `op.viet.vn` and `cloud.viet.vn`. VPC A is configured to use BIND as its DNS server via custom DHCP options.

**Cost Factors:** OP DNS Server (~32$/month)

---

## Scenario 2: All DNS on AWS

**Scenario:** AWS manages DNS for both environments. Route 53 has two PHZs: `cloud.viet.vn` and `op.viet.vn`. BIND becomes a pure forwarder.

**Cost Factors:** OP DNS Server + INBOUND Endpoint Only (~$182/month)

---

## Scenario 3: Split DNS

**Scenario:** Best of both. Route 53 owns `cloud.viet.vn`. BIND owns `op.viet.vn`. They forward cross-domain queries to each other via Resolver endpoints.


**Cost Factor:** OP DNS Server, INBOUND & OUTBOUND Resolver Endpoint (~$365/month)

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

---