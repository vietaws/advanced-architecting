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
# 4. Download demo images from GitHub (vietaws/images:main)
#    These images will be copied to the iSCSI volume after mounting
#    and synced to AWS via Volume Gateway snapshot
# ---------------------------------------------------------------------------
$images = @("flower-1.jpg", "flower-2.jpg", "flower-3.jpg")
$baseUrl = "https://raw.githubusercontent.com/vietaws/images/main"

foreach ($img in $images) {
  $dest = "C:\demo-iscsi\$img"
  try {
    Invoke-WebRequest -Uri "$baseUrl/$img" -OutFile $dest -UseBasicParsing
    Log "Downloaded: $img"
  } catch {
    Log "WARNING: Failed to download $img — $($_.Exception.Message)"
  }
}

Log "Images ready at C:\demo-iscsi\"

# ---------------------------------------------------------------------------
# 5. Set High Performance power plan (avoids latency spikes during demo)
# ---------------------------------------------------------------------------
powercfg /setactive 8c5e7fda-e8bf-4a96-9a85-a6e23a8c635c 2>$null
Log "Power plan set to High Performance"

# ---------------------------------------------------------------------------
# 6. Completion log with next-step instructions
# ---------------------------------------------------------------------------
Log "=== op-iscsi-client setup complete ==="
Log "Next steps for Volume Gateway demo:"
Log "  1. Open iSCSI Initiator: Control Panel > Administrative Tools > iSCSI Initiator"
Log "  2. Discovery tab > Discover Target Portal > enter Storage Gateway appliance private IP"
Log "  3. Targets tab > Connect to volume (port 3260)"
Log "  4. Open Disk Management > Initialize disk > New Simple Volume > Format NTFS > assign drive letter (e.g. Z:)"
Log "  5. Copy demo images to the new drive: Copy-Item C:\demo-iscsi\*.jpg Z:\"
Log "  6. Images on Z:\ will be snapshotted to EBS in AWS via Volume Gateway automatically"
</powershell>
