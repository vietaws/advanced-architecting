# Hybrid DNS — The Problem

## Context

**Viet Corp** runs core systems on-premises under the private domain `op.viet.vn`, managed by a BIND DNS server. As the company moves workloads to AWS, cloud resources live under `cloud.viet.vn`, hosted as a Route 53 private hosted zone in VPC A.

The challenge: **how do resources in both environments find each other by name?**

---

## The Two Environments

```
On-Premises (VPC OP — simulated)       AWS Cloud (VPC A)
────────────────────────────────       ──────────────────────────────
Domain : op.viet.vn                    Domain : cloud.viet.vn
DNS    : BIND at 10.2.1.10             DNS    : Route 53 Private Hosted Zone

Hosts:                                 Hosts:
  dns.op.viet.vn  → 10.2.1.10           app.cloud.viet.vn → 10.1.0.40
  app.op.viet.vn  → 10.2.1.20           web.cloud.viet.vn → 10.1.1.51
  db.op.viet.vn   → 10.2.1.30
```

The two environments are connected via **VPC Peering** (simulating VPN or Direct Connect in production), so IP routing already works. DNS does not.

---

## The Problem

### Problem 1: Cloud → On-Premises name resolution fails

An application on EC2 in VPC A needs to reach `db.op.viet.vn`.

```bash
# From EC2-Cloud (10.1.0.40)
$ dig db.op.viet.vn
;; connection timed out; no servers could be reached
```

VPC A uses Amazon's built-in DNS resolver (`10.1.0.2`). That resolver has no knowledge of `op.viet.vn` — it is a private domain managed by BIND on-premises.

### Problem 2: On-Premises → Cloud name resolution fails

The on-premises app server needs to call `app.cloud.viet.vn`.

```bash
# From App Server (10.2.1.20)
$ dig app.cloud.viet.vn
;; connection timed out; no servers could be reached
```

`cloud.viet.vn` is a Route 53 **private** hosted zone — it only resolves from inside VPC A. On-premises servers cannot reach Route 53 directly.

### Problem 3: AWS service DNS must not break

Some solutions (e.g. pointing VPC A to an on-premises DNS server via custom DHCP) can silently break `s3.amazonaws.com`, EC2 internal hostnames, and instance metadata. This must be handled carefully regardless of which approach is chosen.

---

## What We Need

| Query | Asked by | Expected answer |
|-------|----------|-----------------|
| `app.cloud.viet.vn` | Any host | `10.1.0.40` |
| `db.op.viet.vn` | EC2-Cloud | `10.2.1.30` |
| `app.op.viet.vn` | EC2-Cloud | `10.2.1.20` |
| `app.cloud.viet.vn` | App Server | `10.1.0.40` |
| `s3.amazonaws.com` | EC2-Cloud | AWS-managed endpoint |

---

## Three Approaches

| # | Scenario | Who is authoritative | Best for |
|---|----------|---------------------|----------|
| **Scenario 1** | All DNS on AWS | Route 53 PHZ for both domains | Cloud-first, centralise in AWS |
| **Scenario 2** | All DNS on On-Premises | BIND authoritative for both domains | On-prem team keeps control |
| **Scenario 3** | Split DNS | Route 53 owns `cloud.viet.vn`, BIND owns `op.viet.vn` | Long-term hybrid, best performance |

All three scenarios use the same base infrastructure. The difference is where DNS authority lives and how queries cross environments.