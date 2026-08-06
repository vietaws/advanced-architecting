# Cost Sizing & Breakdown — SGW vs DataSync Demo
**Region:** us-east-1  
**Demo Duration:** 10 hours  
**Pricing Date:** 2026-08-06 (us-east-1 on-demand, no upfront)  
**Exchange:** All prices in USD

---

## Summary: Total Demo Cost

| Pricing Model | EC2 Cost | Managed Services | Total (10 hrs) |
|---------------|----------|-----------------|----------------|
| **All On-Demand** | $5.22 | $2.71 | **~$7.93** |
| **SGW + DataSync agents on Spot** | $2.72 | $2.71 | **~$5.43** |

> Spot saves ~31% ($2.50) by running the two largest instances (SGW appliance + DataSync agent) as Spot. Servers and the Windows iSCSI client remain On-Demand for stability.

---

## Section 1: EC2 Instances

### 1.1 On-Demand Pricing

| Instance Name | Type | OS | On-Demand $/hr | Hours | Subtotal |
|---------------|------|----|---------------|-------|---------|
| `op-nfs-server` | t4g.micro | Amazon Linux 2023 (ARM) | $0.0084 | 10 | $0.08 |
| `op-smb-server` | t4g.micro | Amazon Linux 2023 (ARM) | $0.0084 | 10 | $0.08 |
| `op-iscsi-client` | t3.medium | Windows Server 2022 | $0.0416 | 10 | $0.42 |
| `op-sgw-appliance` | m6i.xlarge | Linux (AWS SGW AMI) | $0.1920 | 10 | $1.92 |
| `op-datasync-agent` | m6a.2xlarge | Linux (AWS DataSync AMI) | $0.3456 | 10 | $3.46 |
| | | | | **Total EC2** | **$5.96** |

> Note: Windows Server 2022 is included in the t3.medium On-Demand price ($0.0416/hr). There is no separate Windows license charge on EC2 for Windows AMIs — it is bundled.

### 1.2 Spot Pricing (SGW Appliance + DataSync Agent)

Running `op-sgw-appliance` and `op-datasync-agent` as Spot reduces cost on the two highest-cost instances. The three smaller instances (NFS server, SMB server, Windows iSCSI client) stay On-Demand to avoid interruption disrupting the demo flow.

| Instance Name | Type | On-Demand $/hr | Spot $/hr (current) | Spot Savings | 10hr Spot Cost |
|---------------|------|---------------|--------------------|--------------|-|
| `op-sgw-appliance` | m6i.xlarge | $0.1920 | $0.1119 | 42% | $1.12 |
| `op-datasync-agent` | m6a.2xlarge | $0.3456 | $0.1600 | 54% | $1.60 |

**Spot prices are current market rates as of 2026-08-06 in us-east-1a. Spot prices fluctuate — check before launching.**

| Scenario | EC2 Total (10 hrs) |
|----------|-------------------|
| All On-Demand | $5.96 |
| SGW + DataSync on Spot, rest On-Demand | $0.08 + $0.08 + $0.42 + $1.12 + $1.60 = **$3.30** |
| **Spot saves** | **$2.66** |

### 1.3 EBS Volumes (Root Disks)

Each EC2 instance has a root EBS volume. Storage Gateway and DataSync AMIs also require a cache/buffer disk.

| Instance | Root Vol | Cache/Buffer Vol | Total EBS (GB) | gp2 $/GB-mo | 10hr Cost |
|----------|----------|-----------------|----------------|-------------|----------|
| `op-nfs-server` | 8 GB gp2 | — | 8 GB | $0.10 | $0.001 |
| `op-smb-server` | 8 GB gp2 | — | 8 GB | $0.10 | $0.001 |
| `op-iscsi-client` | 30 GB gp2 | — | 30 GB | $0.10 | $0.004 |
| `op-sgw-appliance` | 80 GB gp2 (root) | 150 GB gp2 (cache disk) | 230 GB | $0.10 | $0.032 |
| `op-datasync-agent` | 80 GB gp2 (root) | — | 80 GB | $0.10 | $0.011 |
| | | | **Total EBS** | | **$0.05** |

> EBS cost is negligible at 10 hours because billing is per GB-month. 10 hours = 10/730 of a month.
> SGW appliance requires a minimum **150 GB cache disk** (separate from root) attached at launch — see CLI commands in `cli/05-sgw-cli-commands.md`.

---

## Section 2: Managed Services

### 2.1 Amazon S3

| Usage | Rate | Estimated Usage (10hr demo) | Cost |
|-------|------|----------------------------|------|
| Storage (Standard) | $0.023/GB-month | ~5 GB demo data | $0.00016 |
| PUT/COPY/POST requests | $0.005/1000 requests | ~10,000 requests | $0.05 |
| GET requests | $0.0004/1000 requests | ~5,000 requests | $0.002 |
| Data transfer IN | Free | — | $0.00 |
| Data transfer OUT (to internet) | $0.09/GB | ~0 (all intra-AWS/VPC) | $0.00 |
| **S3 Subtotal** | | | **~$0.05** |

> Storage cost rounds to <$0.01 for a 10-hour window. Main S3 cost is request fees from Storage Gateway writes and DataSync task executions.

### 2.2 Amazon EFS

| Usage | Rate | Estimated (10hr demo) | Cost |
|-------|------|-----------------------|------|
| Standard storage | $0.30/GB-month | ~2 GB written (DS-03 NFS→EFS) | $0.00082 |
| **EFS Subtotal** | | | **~$0.001** |

> EFS cost is negligible for a 10-hour demo with small test datasets.

### 2.3 Amazon FSx for Windows File Server

FSx has a **minimum provisioned storage** requirement. The smallest deployable FSx for Windows instance is **32 GB SSD**.

| Component | Rate | Provisioned | Monthly | 10hr Cost |
|-----------|------|-------------|---------|-----------|
| SSD Storage | $0.13/GB-month | 32 GB (minimum) | $4.16 | $0.057 |
| Throughput capacity | $2.20/MBps-month | 8 MBps (minimum) | $17.60 | $0.241 |
| **FSx Subtotal** | | | **~$21.76/mo** | **~$0.30** |

> FSx for Windows has a **minimum throughput capacity of 8 MBps** even at the smallest storage tier, which adds ~$0.24 for 10 hours. This is the highest single managed-service cost in the demo.
> **Cost-saving option:** Skip FSx and use EFS for all DataSync destination demos — saves $0.30 and reduces demo complexity. Document FSx as a supported target verbally. See trade-off note below.

### 2.4 Storage Gateway Service Fees

Storage Gateway charges both an **hourly gateway fee** and **data charges**.

| Fee Type | Rate | Estimated Usage | 10hr Cost |
|----------|------|-----------------|-----------|
| Gateway hourly fee | $0.01/gateway-hour | 1 gateway × 10 hours | $0.10 |
| File GW: data written to S3 | $0.01/GB | ~5 GB written | $0.05 |
| Volume GW: storage used | $0.023/GB-month | ~50 GB volume × 10hr | $0.016 |
| **SGW Service Subtotal** | | | **~$0.17** |

> The SGW service fee ($0.17) is separate from the EC2 appliance cost ($1.92 on-demand). Both apply simultaneously.

### 2.5 AWS DataSync Service Fees

DataSync charges **per GB of data copied** through the service.

| Fee Type | Rate | Estimated Usage | 10hr Cost |
|----------|------|-----------------|-----------|
| Data transfer (all scenarios) | $0.0125/GB | ~20 GB across all tasks | $0.25 |
| **DataSync Service Subtotal** | | | **~$0.25** |

> DataSync agent EC2 cost ($3.46 on-demand or $1.60 spot) is separate from the per-GB service fee.

### 2.6 VPC Interface Endpoints (SSM)

The CFN template creates 3 interface endpoints per VPC = 6 total.

| Resource | Rate | Hours | Cost |
|----------|------|-------|------|
| 6 × SSM/SSMMessages/EC2Messages endpoints | $0.01/endpoint-hour | 10 hrs | $0.60 |
| VPC endpoint data processing | $0.01/GB | ~0.1 GB SSM traffic | $0.001 |
| **VPCE Subtotal** | | | **~$0.60** |

> VPC endpoints are the **second largest cost item** in the managed services section. To save $0.60, you can delete the VPC endpoints after confirming all instances are SSM-reachable (SSM will fall back to internet path via IGW since instances are in public subnets with public IPs). The endpoints are included for reliability and to avoid public internet egress for SSM traffic.

### 2.7 CloudWatch

| Resource | Rate | Usage | Cost |
|----------|------|-------|------|
| Dashboard | $3.00/dashboard-month | 1 dashboard × 10hr | $0.004 |
| Custom metrics (SGW/DataSync push automatically) | Free (AWS service metrics) | — | $0.00 |
| CloudWatch Logs (DataSync task reports) | $0.50/GB ingested | ~0.01 GB | $0.005 |
| Alarms (2 alarms) | $0.10/alarm-month | 2 alarms | $0.003 |
| **CloudWatch Subtotal** | | | **~$0.01** |

---

## Section 3: Full Cost Summary

### 3.1 All On-Demand

| Category | Resource | 10hr Cost |
|----------|----------|-----------|
| EC2 | op-nfs-server (t4g.micro) | $0.08 |
| EC2 | op-smb-server (t4g.micro) | $0.08 |
| EC2 | op-iscsi-client (t3.medium Windows) | $0.42 |
| EC2 | op-sgw-appliance (m6i.xlarge) | $1.92 |
| EC2 | op-datasync-agent (m6a.2xlarge) | $3.46 |
| EBS | All root + cache volumes | $0.05 |
| S3 | Storage + requests | $0.05 |
| EFS | Standard storage | $0.00 |
| FSx | 32 GB + 8 MBps provisioned | $0.30 |
| Storage Gateway | Gateway hours + data fees | $0.17 |
| DataSync | Per-GB transfer fees | $0.25 |
| VPC Endpoints | 6 interface endpoints × 10hr | $0.60 |
| CloudWatch | Dashboard + logs + alarms | $0.01 |
| **TOTAL (On-Demand)** | | **$7.39** |

### 3.2 Optimized with Spot (SGW Appliance + DataSync Agent)

| Category | Resource | 10hr Cost |
|----------|----------|-----------|
| EC2 | op-nfs-server (t4g.micro, On-Demand) | $0.08 |
| EC2 | op-smb-server (t4g.micro, On-Demand) | $0.08 |
| EC2 | op-iscsi-client (t3.medium Windows, On-Demand) | $0.42 |
| EC2 | op-sgw-appliance (m6i.xlarge, **Spot**) | $1.12 |
| EC2 | op-datasync-agent (m6a.2xlarge, **Spot**) | $1.60 |
| EBS | All root + cache volumes | $0.05 |
| S3 | Storage + requests | $0.05 |
| EFS | Standard storage | $0.00 |
| FSx | 32 GB + 8 MBps provisioned | $0.30 |
| Storage Gateway | Gateway hours + data fees | $0.17 |
| DataSync | Per-GB transfer fees | $0.25 |
| VPC Endpoints | 6 interface endpoints × 10hr | $0.60 |
| CloudWatch | Dashboard + logs + alarms | $0.01 |
| **TOTAL (Spot optimized)** | | **$4.73** |

---

## Section 4: Cost Reduction Options

If cost needs to go lower, these are the levers in order of impact:

| Option | Saves | Trade-off |
|--------|-------|-----------|
| Run SGW + DataSync on Spot | $2.66 | Risk of interruption mid-demo (low probability, ~5-10% in us-east-1a during business hours) |
| Skip FSx — use EFS for all DataSync targets | $0.30 | Document FSx support verbally; less realistic for SMB→FSx scenario |
| Remove VPC Endpoints (SSM via IGW) | $0.60 | SSM still works via internet path; slightly higher latency |
| Use t3.small instead of t3.medium for Windows | $0.21 | Windows on t3.small is usable but may be sluggish with iSCSI Initiator UI |
| Reduce DataSync agent to m5.xlarge | $1.73 | Not officially supported for production but works for lab; minimum recommended is m5.2xlarge |

**Minimum viable demo cost (all reductions applied):** ~$1.77 for 10 hours

---

## Section 5: Cleanup Checklist (avoid ongoing charges)

After the demo, delete resources in this order to avoid ongoing charges:

```
Priority  Resource                          Ongoing rate if left running
--------  --------------------------------  ---------------------------
HIGH      FSx for Windows                   $21.76/month minimum
HIGH      VPC Interface Endpoints (6x)      $4.38/month
HIGH      EC2 instances (all 5)             $0 if stopped, $0.20+/mo EBS if kept
MEDIUM    EFS file system                   $0.30/GB-month
MEDIUM    Storage Gateway (service)         $0.01/hour = $7.30/month
LOW       S3 bucket                         $0.023/GB-month (minimal data)
LOW       CloudWatch dashboard/alarms       $3.00/month dashboard
LOW       CloudFormation stack              $0 (just metadata)
```

**Quick cleanup command:**
```bash
# Terminate all 5 demo EC2 instances
aws ec2 terminate-instances --region us-east-1 \
  --instance-ids <nfs-id> <smb-id> <iscsi-id> <sgw-id> <datasync-id>

# Delete FSx file system
aws fsx delete-file-system --region us-east-1 --file-system-id <fsx-id>

# Delete Storage Gateway
aws storagegateway delete-gateway --region us-east-1 --gateway-arn <arn>

# Delete VPC endpoints (get IDs from CFN outputs)
aws ec2 delete-vpc-endpoints --region us-east-1 \
  --vpc-endpoint-ids <vpce-id-1> <vpce-id-2> <vpce-id-3> <vpce-id-4> <vpce-id-5> <vpce-id-6>

# Delete CFN stack (removes VPCs, subnets, SGs, NACLs, EFS, S3 bucket)
aws cloudformation delete-stack --region us-east-1 \
  --stack-name sgw-datasync-demo-network
```

> The CFN stack `delete-stack` will remove the EFS file system and S3 bucket because they are managed by the stack. Ensure the S3 bucket is **empty** before deleting the stack, or enable `ForceDelete` on the bucket resource — the current template does not have a DeletionPolicy set, so a non-empty bucket will cause the stack deletion to fail.

---

## Section 6: CloudWatch Cost Monitoring

The CFN template deploys a CloudWatch dashboard. To track actual spend during the demo, use AWS Cost Explorer or a budget alert:

```bash
# Create a budget alert at $10 for the demo account
aws budgets create-budget \
  --account-id <account-id> \
  --budget '{
    "BudgetName": "sgw-datasync-demo-budget",
    "BudgetLimit": {"Amount": "10", "Unit": "USD"},
    "TimeUnit": "MONTHLY",
    "BudgetType": "COST"
  }' \
  --notifications-with-subscribers '[{
    "Notification": {
      "NotificationType": "ACTUAL",
      "ComparisonOperator": "GREATER_THAN",
      "Threshold": 80
    },
    "Subscribers": [{
      "SubscriptionType": "EMAIL",
      "Address": "your@email.com"
    }]
  }]' \
  --region us-east-1
```

---

*Next: [05-sgw-cli-commands.md](../cli/05-sgw-cli-commands.md) — Storage Gateway appliance provisioning (On-Demand + Spot)*
