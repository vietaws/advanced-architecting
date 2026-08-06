# Demo Scenarios: AWS Storage Gateway vs AWS DataSync
**Ordered:** Easy → Complex  
**Emphasis:** Protocol differences, service behavior, when to use which

---

## Quick Reference: Protocol Support Matrix

| Protocol | Storage Gateway | DataSync |
|----------|----------------|----------|
| NFS v3/v4 | ✅ File Gateway (mount point) | ✅ Source + Destination |
| SMB v2/v3 | ✅ File Gateway (mount point) | ✅ Source + Destination |
| iSCSI | ✅ Volume Gateway + Tape Gateway | ❌ Not supported |
| Amazon S3 API | ❌ | ✅ Source + Destination |
| Amazon EFS | ❌ | ✅ Source + Destination |
| Amazon FSx | ✅ File Gateway (FSx target) | ✅ Source + Destination |
| HDFS | ❌ | ✅ Source only |
| Object Storage (S3-compatible) | ❌ | ✅ Source only |
| VTL (iSCSI tape) | ✅ Tape Gateway | ❌ |

**Key insight:** Storage Gateway provides a **persistent mount point** — applications talk to it like a local file system or block device. DataSync is a **task runner** — you explicitly trigger transfers. Same data, different operational model.

---

## Part 1: AWS Storage Gateway Scenarios

### SGW-01 — File Gateway: NFS Share → Amazon S3 *(Easy)*

**What it shows:** The most fundamental Storage Gateway use case. An on-prem Linux server mounts an NFS share from the gateway; files written to that share silently land in S3.

**Protocol:** NFS v3/v4  
**Source:** `op-nfs-server` (10.1.1.x) — existing NFS server with local data  
**Gateway:** `op-sgw-appliance` (m6i.xlarge, Storage Gateway AMI)  
**Target:** Amazon S3 bucket `demo-sgw-datasync-<accountid>`  

**Demo steps:**
1. In SGW console: create a File Gateway, associate the appliance, create an NFS file share pointing to S3 bucket
2. On `op-nfs-server`: mount the gateway NFS share
   ```bash
   sudo mount -t nfs -o nolock,hard <gateway-ip>:/demo-share /mnt/sgw-nfs
   ```
3. Write a file to the mount:
   ```bash
   echo "Hello from on-prem via NFS" > /mnt/sgw-nfs/test-nfs.txt
   dd if=/dev/urandom bs=1M count=50 of=/mnt/sgw-nfs/large-file.bin
   ```
4. Show the file in S3 console — it appears within seconds
5. Show S3 object metadata: gateway preserves POSIX metadata as S3 object metadata

**Key talking points:**
- The NFS server's application code changed **zero lines** — it still writes to a local path
- S3 object key = file path relative to share root
- Gateway **local cache** on the appliance stores recently written/read data for low-latency access
- Files in S3 are accessible from any AWS service (Lambda, Athena, etc.) immediately

**Differentiator vs DataSync:** This is a live, persistent mount — not a scheduled job. Every write is immediately tiered to S3 in real time.

---

### SGW-02 — File Gateway: SMB Share → Amazon S3 *(Easy)*

**What it shows:** Same concept as SGW-01 but with the SMB protocol, demonstrating Windows-compatible file sharing to S3.

**Protocol:** SMB v2/v3  
**Source:** `op-smb-server` (10.1.1.x) — Samba server  
**Gateway:** `op-sgw-appliance`  
**Target:** Amazon S3 bucket  

**Demo steps:**
1. In SGW console: create an SMB file share on the same gateway, pointing to the same or a separate S3 prefix
2. Configure SMB authentication: choose **Guest access** for demo simplicity (or Active Directory for enterprise realism — document the AD option verbally)
3. On `op-smb-server` (Samba server acting as client for this demo step):
   ```bash
   sudo mount -t cifs //<gateway-ip>/demo-smb-share /mnt/sgw-smb \
     -o username=sgwuser,password=<password>,vers=3.0
   ```
4. Write a file:
   ```bash
   echo "Hello from on-prem via SMB" > /mnt/sgw-smb/test-smb.txt
   ```
5. Show file in S3 console

**Key talking points:**
- Same gateway appliance serves **both NFS and SMB** simultaneously — no separate hardware needed
- SMB is the native Windows file sharing protocol; this enables Windows applications to tier data to S3 without any code change
- For enterprise: integrate with **Active Directory** so existing AD users/groups control access to the SMB share
- ACLs and Windows file permissions are preserved as S3 object metadata

**Differentiator vs DataSync:** DataSync supports SMB as a source but it is a migration/copy tool — no persistent mount is created.

---

### SGW-03 — File Gateway: Cache Behavior & Refresh *(Intermediate)*

**What it shows:** The gateway's local cache — the feature that makes Storage Gateway feel "local" — and how to handle cache staleness when S3 objects are modified outside the gateway.

**Protocol:** NFS v3/v4  
**Source:** `op-nfs-server`  
**Gateway:** `op-sgw-appliance`  
**Target:** Amazon S3 bucket  

**Demo steps:**
1. Mount the NFS share (reuse SGW-01 setup)
2. Write several files through the mount — show they land in S3
3. **Simulate cache hit:** Read a recently written file — observe fast local response (served from cache)
4. **Simulate cache miss + S3 read:** Evict cache by writing enough data to fill it, then read an older file — gateway fetches from S3
5. **Simulate external S3 modification:** Upload a new file directly to S3 via CLI:
   ```bash
   aws s3 cp new-file.txt s3://demo-sgw-datasync-<accountid>/demo-share/new-file.txt
   ```
6. Attempt to see it from the NFS mount — it will **not** appear immediately (cache is stale)
7. Trigger a **cache refresh** via the SGW console (RefreshCache API) or CLI:
   ```bash
   aws storagegateway refresh-cache \
     --file-share-arn arn:aws:storagegateway:us-east-1:<accountid>:share/<shareid>
   ```
8. Show the file now appearing on the NFS mount

**Key talking points:**
- This is the **most common customer confusion point**: "I uploaded directly to S3 but my NFS mount doesn't see it"
- Cache refresh is **eventually consistent** — not instant
- Best practice: write through the gateway, not directly to S3, to avoid cache inconsistency
- Cache size is configurable at gateway provisioning time (local EBS cache disk on the appliance)

---

### SGW-04 — File Gateway: SMB Share → FSx for Windows *(Intermediate)*

**What it shows:** File Gateway can target **FSx for Windows File Server** instead of S3, providing a cloud-native Windows file system that integrates with AD.

**Protocol:** SMB v2/v3  
**Source:** `op-smb-server`  
**Gateway:** `op-sgw-appliance`  
**Target:** Amazon FSx for Windows File Server (`demo-fsx`)  

**Demo steps:**
1. In SGW console: create a new SMB file share, this time pointing to FSx instead of S3
2. Show the configuration difference: FSx share requires the FSx DNS name and credentials
3. Mount the share on `op-smb-server`:
   ```bash
   sudo mount -t cifs //<gateway-ip>/demo-fsx-share /mnt/sgw-fsx \
     -o username=sgwuser,password=<password>,vers=3.0
   ```
4. Write files — show them appearing in FSx via the FSx console
5. Show that FSx files are also accessible from the Cloud VPC directly (mount FSx from a cloud EC2 if desired)

**Key talking points:**
- Use case: on-prem Windows file server wants to extend storage to a **Windows-native cloud file system** (with DFS, shadow copies, AD integration)
- FSx is a fully managed Windows File Server — Microsoft-compatible, supports DFS namespaces
- Contrast with S3 target: FSx gives you Windows semantics (ACLs, NTFS permissions, shadow copies); S3 gives you object storage (cheaper, more scalable, accessible to any AWS service)

---

### SGW-05 — Volume Gateway: Cached Mode → EBS *(Intermediate)*

**What it shows:** Volume Gateway Cached Mode — the gateway presents an iSCSI block device to the Windows client. Primary data lives in S3 (via EBS under the hood); hot data is cached locally on the appliance.

**Protocol:** iSCSI  
**Client:** `op-iscsi-client` (Windows Server t3.medium)  
**Gateway:** `op-sgw-appliance`  
**Target:** S3 (gateway-managed EBS snapshots in background)  

**Demo steps:**
1. In SGW console: create a **Volume Gateway**, configure a **Cached Volume** (e.g., 50 GB)
2. Note the **local cache allocation** on the appliance (separate EBS disk) vs total volume size stored in S3
3. On `op-iscsi-client` (Windows Server), open **iSCSI Initiator** (Control Panel → Administrative Tools → iSCSI Initiator):
   - Target portal: enter the gateway IP
   - Discover targets → connect to the volume
4. Open **Disk Management** — the iSCSI volume appears as a new raw disk
5. Initialize, partition (GPT), format (NTFS), assign drive letter (e.g., `Z:`)
6. Write files to `Z:\` — copy a folder, create documents
7. In SGW console: show the volume, trigger a manual **EBS snapshot**
8. Show the snapshot in EC2 → Snapshots console

**Key talking points (Windows GUI advantage):**
- The audience **sees** a disk appear in Disk Management — instantly understood as "local storage"
- This is exactly how it looks on a real on-prem Windows server — the application has no idea data is going to AWS
- iSCSI is a **block protocol** — not file-level. The OS formats the disk and manages the file system. This is fundamentally different from NFS/SMB
- Cached mode: only hot data stays local. Full dataset lives in S3. Great for large datasets with limited local storage
- Snapshots can be used to create EBS volumes in AWS (disaster recovery, cloud migration)

**Differentiator vs DataSync:** DataSync does not support iSCSI. There is no DataSync equivalent for this scenario.

---

### SGW-06 — Volume Gateway: Stored Mode → EBS Snapshot *(Advanced)*

**What it shows:** Volume Gateway Stored Mode — the opposite of Cached Mode. Full dataset lives **locally** on the appliance; S3/EBS is used only for asynchronous backup snapshots.

**Protocol:** iSCSI  
**Client:** `op-iscsi-client` (Windows Server t3.medium)  
**Gateway:** `op-sgw-appliance`  
**Target:** EBS snapshots (async backup to S3)  

**Demo steps:**
1. In SGW console: create a **Stored Volume** on the same gateway (use a small size, e.g., 20 GB)
2. Connect from `op-iscsi-client` iSCSI Initiator — same steps as SGW-05 but different volume
3. Format and write data to the new drive
4. Show in SGW console: **Upload buffer** and **Cache** metrics — stored mode shows full data locally
5. Trigger a snapshot — observe it is asynchronous (data is already written locally, snapshot uploads in background)
6. **Compare directly with Cached Mode:** Open both volumes in SGW console side by side:
   - Cached: local cache % used, total size in S3
   - Stored: local storage % used, snapshot schedule

**Key talking points:**
- Stored mode is for customers who need **full local performance** with cloud backup as a side effect
- Cached mode is for customers with **limited local storage** who want full dataset in the cloud
- Both use iSCSI — the client (Windows) cannot tell the difference
- The snapshot can be converted to a full EBS volume for cloud migration (create AMI from snapshot → run in EC2)
- Disaster recovery use case: on-prem server fails → restore from latest EBS snapshot in minutes

---

---

## Part 2: AWS DataSync Scenarios

### DS-01 — DataSync: NFS → Amazon S3 (One-Time Task) *(Easy)*

**What it shows:** The most basic DataSync use case. Define a task to copy data from the on-prem NFS server to S3. Run it once. This is the DataSync equivalent entry point to SGW-01.

**Protocol:** NFS v3/v4 (source), S3 API (destination)  
**Source:** `op-nfs-server` `/data/nfs-share` (NFS export)  
**Agent:** `op-datasync-agent` (m6a.2xlarge, DataSync Agent AMI)  
**Target:** Amazon S3 bucket `demo-sgw-datasync-<accountid>`/datasync-nfs/  

**Demo steps:**
1. In DataSync console: the agent should already be activated — show its status as **Online**
2. Create a **source location**: NFS — enter agent ARN, NFS server IP (`op-nfs-server`), export path `/data/nfs-share`
3. Create a **destination location**: S3 — select bucket and prefix `datasync-nfs/`, select IAM role
4. Create a **task**: select source + destination, leave all options default
5. Start the task manually — **Execute task**
6. Watch the task **progress in real time**: files transferred, bytes transferred, throughput (MB/s)
7. When complete: show files in S3 under `datasync-nfs/` prefix
8. Show **task report** in CloudWatch Logs: per-file transfer status, checksum verification results

**Key talking points:**
- DataSync requires an **explicit action** to move data — nothing moves until you run the task
- The **agent** in the on-prem VPC connects to the NFS server locally (high-speed LAN), then transfers to S3 over the network
- DataSync performs **end-to-end integrity checksums** automatically — every file is verified at source and destination
- Throughput is automatically optimized with parallel streams — no tuning required

**Differentiator vs SGW-01:** SGW-01 data moved because someone wrote to the NFS mount. DS-01 data moves because an operator triggered a task. Same files in S3 at the end — completely different operational model.

---

### DS-02 — DataSync: SMB → FSx for Windows (One-Time Task) *(Easy)*

**What it shows:** DataSync migrating SMB file share data to FSx for Windows — a common migration scenario from on-prem Windows file servers to cloud-native Windows file storage.

**Protocol:** SMB v2/v3 (source), FSx API (destination)  
**Source:** `op-smb-server` Samba share `//10.1.1.x/demo`  
**Agent:** `op-datasync-agent`  
**Target:** Amazon FSx for Windows File Server (`demo-fsx`)  

**Demo steps:**
1. Create a **source location**: SMB — enter agent ARN, SMB server IP, share name `demo`, credentials
2. Create a **destination location**: FSx for Windows — select the FSx file system, subdirectory `/datasync-smb`
3. Create and run the task
4. Show transfer progress in DataSync console
5. Verify files in FSx console or by mounting FSx from a cloud EC2

**Key talking points:**
- Use case: **Windows file server migration** to FSx — one of the most common enterprise migration scenarios
- DataSync preserves **NTFS ACLs, timestamps, and file attributes** when transferring to FSx
- This is a migration tool — after migration, users switch to accessing FSx directly; the on-prem share can be decommissioned
- Contrast with SGW-04: SGW-04 keeps the on-prem share alive permanently (ongoing tiering); DS-02 moves data and ends (migration/cutover)

---

### DS-03 — DataSync: NFS → Amazon EFS (Scheduled Task) *(Intermediate)*

**What it shows:** DataSync with a **schedule** — automatically sync on-prem NFS data to EFS on a recurring basis. Also shows EFS as a target (NFS-compatible cloud file system).

**Protocol:** NFS v3/v4 (source + destination)  
**Source:** `op-nfs-server` `/data/nfs-share`  
**Agent:** `op-datasync-agent`  
**Target:** Amazon EFS `demo-efs` (mounted in Cloud VPC)  

**Demo steps:**
1. Create a **source location**: NFS (same as DS-01)
2. Create a **destination location**: EFS — select the EFS file system, subdirectory `/datasync-efs`
3. Create a task with a **schedule**: every 1 hour (for demo, use every 15 minutes via cron: `0/15 * * * ? *`)
4. Show the schedule configuration in the task settings
5. Add a new file to the NFS server: `echo "scheduled sync test" > /data/nfs-share/scheduled-test.txt`
6. Wait for the next scheduled run (or trigger manually) — show the file appearing in EFS
7. Show **task execution history** — multiple runs with timestamps and file counts

**Key talking points:**
- EFS is a **serverless NFS file system** — no servers to manage, scales automatically, accessible from any EC2 in the VPC via NFS
- Schedule = DataSync becomes a **continuous replication** tool when run frequently
- Use case: on-prem NFS data needs to be available in the cloud for analytics, ML training, or disaster recovery
- EFS supports NFSv4 natively — data transferred from on-prem NFS lands in a cloud NFS system with no protocol translation
- Preserves POSIX permissions, ownership, timestamps

---

### DS-04 — DataSync: Filtering, Bandwidth Throttling & Transfer Options *(Intermediate)*

**What it shows:** DataSync's advanced task configuration — filtering files, throttling bandwidth, and controlling what gets transferred. This is where DataSync shows its operational sophistication.

**Protocol:** NFS v3/v4 (source), S3 (destination)  
**Source:** `op-nfs-server` `/data/nfs-share`  
**Agent:** `op-datasync-agent`  
**Target:** Amazon S3 bucket, prefix `datasync-filtered/`  

**Demo steps:**

**Part A — Filtering:**
1. Create a new task (or modify DS-01) with **include/exclude filters**
2. Add an include filter: `*.txt` — only transfer text files
3. Add an exclude filter: `*/tmp/*` — skip any `tmp` subdirectory
4. Populate the NFS share with mixed files:
   ```bash
   echo "include me" > /data/nfs-share/report.txt
   dd if=/dev/urandom bs=1M count=10 of=/data/nfs-share/binary.bin
   mkdir -p /data/nfs-share/tmp && echo "skip me" > /data/nfs-share/tmp/temp.txt
   ```
5. Run the task — show only `report.txt` transferred, `binary.bin` and `tmp/` skipped
6. Show the **skipped files** count in the task execution report

**Part B — Bandwidth Throttling:**
1. Edit the task: set **Bandwidth limit** to 10 MB/s
2. Run a transfer with a large file — show throughput capped in CloudWatch metrics
3. Remove the limit — show throughput jump to maximum available
4. Use case: transfer during business hours without impacting production network

**Part C — Transfer mode options:**
1. Show **"Transfer only data that has changed"** (default) vs **"Transfer all data"**
2. Run the task twice — second run should show 0 files transferred (no changes)
3. Modify one file on NFS — run again — show only that file transferred

**Key talking points:**
- Storage Gateway has **no filtering** — it mirrors everything written to the share mount
- DataSync gives you precise control over what moves, when, and at what speed
- The **changed-data-only** mode makes DataSync efficient for large datasets with small daily deltas
- Bandwidth throttling is critical for production environments — protect application traffic

---

### DS-05 — DataSync: Integrity Verification + CloudWatch Monitoring *(Advanced)*

**What it shows:** DataSync's built-in integrity verification and how to monitor both DataSync and Storage Gateway using CloudWatch — the comparison capstone scenario.

**Protocol:** NFS v3/v4 (source), S3 (destination)  
**Source:** `op-nfs-server`  
**Agent:** `op-datasync-agent`  
**Monitoring:** Amazon CloudWatch (dashboards + alarms)  

**Demo steps:**

**Part A — Integrity verification:**
1. Run a DataSync task with **Verify data** setting = `ONLY_FILES_TRANSFERRED` (default) vs `ALL_FILES_IN_DESTINATION`
2. Explain the three verification modes:
   - `NONE`: no checksum verification (fastest, use for non-critical data)
   - `ONLY_FILES_TRANSFERRED`: verify only files moved in this task execution (default, balanced)
   - `ALL_FILES_IN_DESTINATION`: verify entire destination matches source (slowest, use for compliance)
3. Show in CloudWatch Logs: per-file `TRANSFERRED` status with checksum result
4. **Simulate a corruption:** manually modify a file in S3 after transfer, re-run with `ALL_FILES_IN_DESTINATION` — show the file flagged as different in logs

**Part B — CloudWatch Dashboard comparison:**
1. Open the CloudWatch dashboard (deployed with CFN stack)
2. **DataSync metrics panel:**
   - `FilesTransferred` — files successfully moved per task execution
   - `BytesTransferred` — throughput over time
   - `FilesVerified` — integrity check count
   - `TaskExecutionStatus` — SUCCESS / ERROR / RUNNING
3. **Storage Gateway metrics panel:**
   - `CacheHitPercent` — % of reads served from local cache vs fetched from S3
   - `CacheUsed` — local cache utilization
   - `CloudBytesUploaded` / `CloudBytesDownloaded` — data flow to/from S3
   - `ReadBytes` / `WriteBytes` — throughput at the NFS/SMB mount
4. Show an **alarm**: alert when `CacheHitPercent` drops below 50% (indicates cache is too small or data is too cold)

**Key talking points:**
- DataSync gives you **per-file audit trail** in CloudWatch Logs — you know exactly which files moved and whether they are bit-perfect
- Storage Gateway gives you **operational metrics** — is the cache sized correctly? Is data being written/read at expected rates?
- These metrics serve different purposes: DataSync metrics answer "did my migration complete correctly?"; SGW metrics answer "is my hybrid storage healthy?"
- For compliance/regulatory workloads, DataSync's checksum verification provides an auditable proof of data integrity

---

## Part 3: Side-by-Side Comparison Scenario

### COMPARE-01 — Same Source, Same Target, Different Service *(Capstone)*

**What it shows:** The definitive comparison. The exact same data on the same NFS server gets moved to S3 by both services. The audience sees the different operational models converge on the same result.

**Setup:**
- NFS server has `/data/nfs-share/compare-test/` with 100 files (~500 MB total)
- Both services target the same S3 bucket, different prefixes: `sgw-compare/` and `datasync-compare/`

**Step 1 — Storage Gateway path:**
1. NFS share is already mounted on `op-nfs-server` via SGW (SGW-01 setup)
2. Copy test data to the SGW mount:
   ```bash
   cp -r /data/nfs-share/compare-test/ /mnt/sgw-nfs/compare-test/
   ```
3. Files appear in `s3://demo.../sgw-compare/` within seconds — **no explicit action needed**

**Step 2 — DataSync path:**
1. Run a DataSync task with source `/data/nfs-share/compare-test/`, destination `s3://demo.../datasync-compare/`
2. Explicitly start the task — watch progress bar
3. Task completes — files appear in `s3://demo.../datasync-compare/`

**Step 3 — Compare in S3 console:**
- Both prefixes have identical files
- SGW objects: metadata includes POSIX attributes from gateway
- DataSync objects: metadata includes DataSync transfer attributes + checksum

**Discussion framework for customers:**

| Question | Storage Gateway | DataSync |
|----------|----------------|----------|
| Did I need to change my application? | No | Yes (trigger the task) |
| Is data moved in real-time? | Yes (on write) | Only when task runs |
| Do I get transfer verification? | No | Yes (checksums) |
| Can I filter what gets moved? | No | Yes |
| Can I throttle bandwidth? | Indirectly (QoS on appliance) | Yes, per-task setting |
| Does it work after the demo ends? | Yes (persistent mount) | Only when scheduled/triggered |
| What's the ongoing cost? | Gateway hourly + storage | Per-GB transferred + agent |
| Best for | Ongoing hybrid access | Migration, scheduled sync |

---

## Summary: When to Recommend Each Service

### Recommend Storage Gateway when:
- The customer cannot change application code (legacy apps writing to NFS/SMB/iSCSI)
- Real-time, low-latency access to cloud data from on-prem is required
- The use case is **ongoing** (not a one-time migration)
- Replacing aging NAS/SAN hardware without touching applications
- Backup software needs a local tape library (Tape Gateway)

### Recommend DataSync when:
- The goal is **migration** — move data to cloud and decommission on-prem storage
- **Data integrity verification** is required (compliance, regulated industries)
- The transfer needs **scheduling, filtering, or bandwidth control**
- Moving data between AWS services (EFS to S3, S3 to FSx, etc.)
- Large one-time bulk transfers where throughput optimization matters

### Recommend Both when:
- **Migrate with DataSync first** (bulk copy), then **switch to Storage Gateway** for ongoing hybrid access
- This is the recommended migration pattern for large NAS → cloud file storage projects

---

*Next: [03-cloudformation.yaml](../cfn/03-cloudformation.yaml) — Network foundation template*
