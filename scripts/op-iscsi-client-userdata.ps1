<powershell>
# =============================================================================
# op-iscsi-client-userdata.ps1
# EC2 User Data — OP iSCSI Client (t3.medium, Windows Server 2022)
# Enables iSCSI Initiator service, prepares for Volume Gateway demo
# =============================================================================

$logFile = "C:\demo-setup.log"
function Log($msg) {
  $line = "$((Get-Date).ToString('yyyy-MM-dd HH:mm:ss')) $msg"
  $line | Tee-Object -FilePath $logFile -Append | Write-Host
}

Log "=== Starting op-iscsi-client setup ==="

# ---------------------------------------------------------------------------
# 1. Enable and start iSCSI Initiator service
# ---------------------------------------------------------------------------
Set-Service  -Name MSiSCSI -StartupType Automatic
Start-Service -Name MSiSCSI
Log "iSCSI Initiator service started"

# ---------------------------------------------------------------------------
# 2. Enable iSCSI firewall rules
# ---------------------------------------------------------------------------
Enable-NetFirewallRule -DisplayGroup "iSCSI Service" -ErrorAction SilentlyContinue
Log "iSCSI firewall rules enabled"

# ---------------------------------------------------------------------------
# 3. Create demo working folder for post-mount content
# ---------------------------------------------------------------------------
New-Item -ItemType Directory -Force -Path "C:\demo-iscsi" | Out-Null
Log "C:\demo-iscsi folder created"

# ---------------------------------------------------------------------------
# 4. Set High Performance power plan (avoids latency spikes during demo)
# ---------------------------------------------------------------------------
powercfg /setactive 8c5e7fda-e8bf-4a96-9a85-a6e23a8c635c 2>$null
Log "Power plan set to High Performance"

# ---------------------------------------------------------------------------
# 5. Completion log with next-step instructions
# ---------------------------------------------------------------------------
Log "=== op-iscsi-client setup complete ==="
Log "Next steps for Volume Gateway demo:"
Log "  1. Open iSCSI Initiator: Control Panel > Administrative Tools > iSCSI Initiator"
Log "  2. Discovery tab > Discover Target Portal > enter Storage Gateway appliance private IP"
Log "  3. Targets tab > Connect to volume (port 3260)"
Log "  4. Open Disk Management > Initialize disk > New Simple Volume > Format NTFS > assign drive letter"
Log "  5. Write files to new drive — data snapshots to EBS in AWS automatically"
</powershell>
