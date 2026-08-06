# Demo Plan: AWS Storage Gateway vs AWS DataSync
**Region:** us-east-1  
**Audience:** Customer-facing (technical)  
**Duration:** ~10 hours total infrastructure runtime  
**Last Updated:** 2026-08-06

---

## 1. Overview & Purpose

This demo compares two AWS hybrid storage services that are frequently confused by customers:

| | AWS Storage Gateway | AWS DataSync |
|---|---|---|
| **Primary use case** | Ongoing, low-latency hybrid access to cloud storage from on-premises applications | Scheduled or one-time bulk data transfer/migration between storage systems |
| **Access model** | Persistent mount point — applications see a local file system or block device | Task-based pipeline — define source, destination, and schedule |
| **Protocol support** | NFS, SMB (File GW), iSCSI (Volume GW), VTL (Tape GW) | NFS, SMB, Amazon S3 API, EFS, FSx, HDFS, object storage |
| **Latency** | Low (local cache on gateway appliance) | Optimized for throughput, not real-time access |
| **Best for** | Lift-and-shift, tiering, backup with local access | Migration, replication, archival pipelines |

The demo runs both services in a **single shared environment** so the audience can directly compare behavior, configuration complexity, and use-case fit.

---

## 2. Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                        AWS Cloud VPC                            │
│                    CIDR: 10.0.0.0/16  (us-east-1)              │
│                                                                 │
│  AZ us-east-1a                    AZ us-east-1b                 │
│  ┌─────────────────┐              ┌─────────────────┐           │
│  │ Public Subnet   │              │ Public Subnet   │           │
│  │ 10.0.1.0/24     │              │ 10.0.2.0/24     │           │
│  │                 │              │                 │           │
│  │  [S3 Endpoint]  │              │                 │           │
│  │  [EFS Mount TGT]│              │  [EFS Mount TGT]│           │
│  └─────────────────┘              └─────────────────┘           │
│  ┌─────────────────┐              ┌─────────────────┐           │
│  │ Private Subnet  │              │ Private Subnet  │           │
│  │ 10.0.101.0/24   │              │ 10.0.102.0/24   │           │
│  └─────────────────┘              └─────────────────┘           │
│                                                                 │
│  Managed Services (no VPC placement):                           │
│    - Amazon S3 (bucket: demo-sgw-datasync-<account>)            │
│    - Amazon EFS (demo-efs)                                      │
│    - Amazon FSx for Windows File Server (demo-fsx)              │
└─────────────────────────────────────────────────────────────────┘
                         │
                    VPC Peering
                 (no NAT required)
                         │
┌─────────────────────────────────────────────────────────────────┐
│               Simulated On-Premises VPC                         │
│                    CIDR: 10.1.0.0/16  (us-east-1)              │
│                                                                 │
│  AZ us-east-1a                    AZ us-east-1b                 │
│  ┌─────────────────────────────────────────────────────┐        │
│  │ Public Subnet 10.1.1.0/24   Public Subnet 10.1.2.0/24│       │
│  │                                                     │        │
│  │  [NFS Server]     [SMB Server]    [Windows iSCSI]   │        │
│  │  t4g.micro        t4g.micro       t3.medium          │        │
│  │  Amazon Linux 2   Amazon Linux 2  Windows Server     │        │
│  │  (NFS exports)    (Samba)         (iSCSI Initiator)  │        │
│  │                                                     │        │
│  │  [Storage Gateway Appliance]  [DataSync Agent]      │        │
│  │  m6i.xlarge                   m6a.2xlarge           │        │
│  │  (AWS SGW AMI)                (AWS DataSync AMI)    │        │
│  └─────────────────────────────────────────────────────┘        │
│  ┌─────────────────────────────────────────────────────┐        │
│  │ Private Subnet 10.1.101.0/24  Private Subnet 10.1.102.0/24│  │
│  │  (reserved, no instances)                           │        │
│  └─────────────────────────────────────────────────────┘        │
└─────────────────────────────────────────────────────────────────┘
```

---

## 3. Instance Inventory

All instances are created manually via AWS CLI or Management Console after the CloudFormation network stack is deployed.

| # | Name | VPC | Subnet | Instance Type | OS | Role | Created By |
|---|------|-----|--------|---------------|----|------|------------|
| 1 | `op-nfs-server` | On-Prem | Public 1a (10.1.1.0/24) | t4g.micro | Amazon Linux 2023 (ARM) | NFS export source for both SGW and DataSync demos | Manual |
| 2 | `op-smb-server` | On-Prem | Public 1a (10.1.1.0/24) | t4g.micro | Amazon Linux 2023 (ARM) | Samba SMB export source for both SGW and DataSync demos | Manual |
| 3 | `op-iscsi-client` | On-Prem | Public 1a (10.1.1.0/24) | t3.medium | Windows Server 2022 | iSCSI Initiator for Volume Gateway demo | Manual |
| 4 | `op-sgw-appliance` | On-Prem | Public 1a (10.1.1.0/24) | m6i.xlarge | AWS Storage Gateway AMI | Storage Gateway appliance (File + Volume) | Manual |
| 5 | `op-datasync-agent` | On-Prem | Public 1a (10.1.1.0/24) | m6a.2xlarge | AWS DataSync Agent AMI | DataSync agent for NFS/SMB source transfers | Manual |

**Total: 5 EC2 instances + managed services (S3, EFS, FSx)**

---

## 4. Why This Architecture

### 4.1 Single Storage Gateway Appliance (File + Volume)
One m6i.xlarge appliance handles all File Gateway (NFS + SMB shares) and Volume Gateway (cached + stored iSCSI) scenarios. This is realistic — enterprise customers deploy a single appliance per site. Running separate appliances would double the largest cost line item unnecessarily.

### 4.2 Separate NFS and SMB Source Servers
Using two dedicated source servers (one for NFS, one for SMB via Samba) provides clean, isolated demo segments. The audience can clearly see:
- NFS server → File Gateway NFS share → S3
- SMB server → File Gateway SMB share → S3/FSx
- NFS server → DataSync task → S3/EFS
- SMB server → DataSync task → FSx for Windows

Combining them on one server would create confusion during live demos.

### 4.3 Windows t3.medium for iSCSI Client
The Volume Gateway iSCSI demo uses a **Windows Server t3.medium** instead of a Linux instance. This is a deliberate customer experience choice:

- **Windows iSCSI Initiator** is a built-in GUI tool (Control Panel → iSCSI Initiator) that visually shows volume discovery, connection, and disk mounting — highly intuitive for customer audiences
- Demonstrates the most common real-world use case: Windows application servers accessing block storage
- The audience sees a disk appear in **Disk Management** and immediately understands the "local storage feel" that Storage Gateway provides
- Cost premium over Linux: ~$0.25 for 10 hours — negligible

### 4.4 All Instances in Public Subnets (No NAT Gateway)
To minimize cost and complexity, all demo instances are placed in public subnets with:
- Public IPs assigned (for SSM endpoints and service activation)
- SSM Session Manager for all access (no bastion, no SSH key management)
- Security Groups restrict all inbound traffic except necessary service ports
- Private subnets exist in the template for architectural completeness but hold no instances

This saves ~$0.045/hr per NAT Gateway ($0.90 for 10 hours per AZ = $1.80 saved).

### 4.5 VPC Peering Instead of Transit Gateway or VPN
VPC Peering is the simplest and cheapest connectivity option for this demo. It accurately simulates the network path between on-premises and cloud without the overhead of TGW ($0.05/hr attachment + processing) or the complexity of VPN configuration.

### 4.6 SSM Session Manager for All Access
- No bastion host required (saves one EC2 instance)
- No SSH key pair management
- Works on both Linux (Amazon Linux 2023) and Windows Server 2022
- All instances are in **public subnets with public IPs** — SSM Agent reaches the SSM service endpoints via the IGW directly. No VPC interface endpoints required.
- Requires IAM role `ec2-instance-role` attached to all instances (pre-created outside the demo stack)

---

## 5. Managed Services Used

| Service | Resource Name | Purpose |
|---------|--------------|---------|
| Amazon S3 | `demo-sgw-datasync-<accountid>` | Target for File Gateway NFS/SMB and DataSync transfers |
| Amazon EFS | `demo-efs` | DataSync target for NFS-sourced transfers |
| FSx for Windows | `demo-fsx` | DataSync target for SMB-sourced transfers; also File Gateway SMB target |
| CloudWatch | Dashboards + Alarms | Monitor SGW cache hit rate, DataSync transfer throughput, errors |

---

## 6. Key Differentiators to Emphasize During Demo

### Storage Gateway — "Hybrid Storage Extension"
- Applications on-prem **never change** — they still read/write to a local NFS/SMB mount or iSCSI disk
- Data is **transparently tiered** to S3/FSx/EBS in the cloud
- **Local cache** on the appliance provides low-latency reads for hot data
- Ideal for: lift-and-shift, backup with local access, cloud tiering without app changes

### DataSync — "Intelligent Data Mover"
- Explicitly **task-based**: you define what to move, where, and when
- Transfers are **optimized**: parallel multi-part, compression, integrity checksums end-to-end
- No persistent mount — once the task runs, the connection is not maintained
- Ideal for: migration to cloud, cross-service replication, archival pipelines

### Side-by-Side Comparison Point
> **Same NFS server, same data** — in the Storage Gateway demo, the NFS server mounts the gateway share and writes a file; the file silently lands in S3. In the DataSync demo, a task is explicitly triggered to move files from the same NFS server to S3. The audience sees the same outcome but with a fundamentally different operational model.

---

## 7. Demo Flow Summary

```
Phase 1: Environment Setup (CFN + Manual provisioning)
  └─ Deploy CFN stack (VPCs, subnets, peering, SGs, NACLs)
  └─ Provision instances manually (5 EC2 + S3 + EFS + FSx)
  └─ Configure NFS server, SMB server, activate gateway + agent

Phase 2: DataSync Scenarios
  └─ DS-01: DataSync NFS → S3 (basic one-time task)
  └─ DS-02: DataSync SMB → FSx (basic one-time task)
  └─ DS-03: DataSync NFS → EFS (with scheduling)
  └─ DS-04: DataSync with filtering, bandwidth throttling
  └─ DS-05: DataSync NFS → S3 with integrity verification + CloudWatch

Phase 3: Storage Gateway Scenarios (File Gateway)
  └─ SGW-01: File Gateway NFS → S3 (basic)
  └─ SGW-02: File Gateway SMB → S3 (basic)
  └─ SGW-03: File Gateway NFS → S3 (cache behavior, refresh)
  └─ SGW-04: File Gateway SMB → FSx for Windows

Phase 4: Storage Gateway Scenarios (Volume Gateway)
  └─ SGW-05: Volume Gateway Cached Mode → EBS (Windows iSCSI)
  └─ SGW-06: Volume Gateway Stored Mode → EBS snapshot (Windows iSCSI)

Phase 5: Comparison & Wrap-up
  └─ Side-by-side: same data, same NFS source, different service behavior
  └─ CloudWatch metrics comparison
  └─ When to use which service (decision framework)
```

---

## 8. Pre-Demo Checklist

- [ ] CloudFormation stack deployed successfully
- [ ] IAM role `ec2-instance-role` exists with SSM + S3 + EFS + FSx permissions
- [ ] 5 EC2 instances running and SSM-reachable
- [ ] NFS server: `/data/nfs-share` exported, test files present
- [ ] SMB server: Samba share `demo` configured, test files present
- [ ] Storage Gateway appliance: activated and visible in SGW console
- [ ] DataSync agent: activated and visible in DataSync console
- [ ] S3 bucket created, EFS file system mounted to cloud VPC, FSx available
- [ ] CloudWatch dashboard deployed
- [ ] Windows iSCSI Initiator: iSCSI service running on `op-iscsi-client`

---

## 9. Tape Gateway (Reference Only)

Tape Gateway is **not demonstrated live** in this demo. Key reference points for the audience:

- Emulates a **Virtual Tape Library (VTL)** — works with existing backup software (Veeam, Veritas, Commvault, etc.) without changes
- Protocol: **iSCSI** (same as Volume Gateway, different use case)
- Tapes written to the gateway are stored in **S3**, then archived to **S3 Glacier** or **S3 Glacier Deep Archive**
- Use case: replace physical tape infrastructure, keeping backup software and procedures unchanged
- Cost model: pay per GB stored in S3/Glacier, no minimum tape size
- Why not demoed: requires a backup application (Veeam, etc.) to be installed and configured — high setup cost for demo time; the concept is better conveyed with slides/architecture diagram

---

*Next: [02-scenarios.md](./02-scenarios.md) — Full scenario list, easy to complex*
