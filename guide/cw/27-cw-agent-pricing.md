 ## CloudWatch Agent Cost: FREE

The CloudWatch Agent itself is FREE - there's no charge for installing or running it.

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━


## What You Pay For

You only pay for the data it sends to CloudWatch:

### 1. Metrics Cost

Standard metrics (CPU, Memory, Disk, etc.):
- **Cost**: $0.30 per metric per month
- Agent typically collects 5-10 metrics per instance

Example:
Metrics collected by agent:
- CPU_IDLE
- MEMORY_USED  
- DISK_USED
- DISK_IO_TIME
- TCP_CONNECTIONS
- SWAP_USED

Total: 6 metrics × $0.30 = $1.80/month per instance


━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━


### 2. Logs Cost

Log ingestion: $0.50 per GB
Log storage: $0.03 per GB per month

Example:
1 GB logs per day:
- Ingestion: 30 GB × $0.50 = $15.00/month
- Storage: 30 GB × $0.03 = $0.90/month
Total: $15.90/month


━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━


## Cost Breakdown Example

### Scenario: 1 EC2 instance with CloudWatch Agent

Component                              Cost
──────────────────────────────────────────────
CloudWatch Agent software              $0.00 (FREE)
Agent installation                     $0.00 (FREE)
Agent running/CPU usage                $0.00 (FREE)

Metrics (6 system metrics)             $1.80
Logs (1 GB/day = 30 GB/month)          $15.90
──────────────────────────────────────────────
TOTAL                                  $17.70/month


━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━


## Cost Comparison: With vs Without Agent

### Without CloudWatch Agent

Default EC2 metrics (Basic monitoring):
- CPU, Network, Disk I/O
- **Cost**: $0 (FREE)
- **Limitation**: No memory, no disk usage, 5-minute intervals

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━


### With CloudWatch Agent

Enhanced metrics:
- CPU, Memory, Disk usage, Disk I/O, Network, Swap, TCP connections
- **Cost**: ~$1.80/month for metrics
- **Benefit**: Memory monitoring, disk usage, 1-minute intervals

Plus logs:
- Application logs sent to CloudWatch
- **Cost**: $0.50/GB ingestion + $0.03/GB storage
- **Benefit**: Centralized log management, searchable with Logs Insights

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━


## Real-World Cost Examples

### Example 1: Small Application (1 instance)

CloudWatch Agent: FREE
Metrics (6): $1.80/month
Logs (500 MB/day): $7.95/month
─────────────────────────────
TOTAL: $9.75/month


━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━


### Example 2: Medium Application (10 instances)

CloudWatch Agent: FREE
Metrics (6 × 10): $18.00/month
Logs (5 GB/day total): $79.50/month
─────────────────────────────
TOTAL: $97.50/month


━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━


### Example 3: Large Application (100 instances)

CloudWatch Agent: FREE
Metrics (6 × 100): $180.00/month
Logs (50 GB/day total): $795.00/month
─────────────────────────────
TOTAL: $975.00/month


━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━


## Cost Optimization Tips

### 1. Reduce Metrics Collected

Default config (6 metrics):
json
{
  "metrics_collected": {
    "cpu": {...},
    "mem": {...},
    "disk": {...},
    "diskio": {...},
    "netstat": {...},
    "swap": {...}
  }
}

Cost: $1.80/month

Minimal config (2 metrics):
json
{
  "metrics_collected": {
    "cpu": {...},
    "mem": {...}
  }
}

Cost: $0.60/month
Savings: $1.20/month per instance

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━


### 2. Reduce Log Volume

Filter logs before sending:
json
{
  "logs": {
    "logs_collected": {
      "files": {
        "collect_list": [
          {
            "file_path": "/var/log/app/error.log",  // Only errors
            "log_group_name": "/aws/ec2/app"
          }
        ]
      }
    }
  }
}


Savings: If you reduce from 1 GB/day to 100 MB/day:
- Before: $15.90/month
- After: $1.59/month
- **Savings**: $14.31/month

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━


### 3. Set Log Retention

bash
# Set 7-day retention instead of default (never expire)
aws logs put-retention-policy \
  --log-group-name /aws/ec2/app \
  --retention-in-days 7


Savings: Storage cost reduced by ~75%

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━


### 4. Increase Collection Interval

Default (60 seconds):
json
{
  "metrics_collection_interval": 60
}


Relaxed (300 seconds):
json
{
  "metrics_collection_interval": 300
}


Note: This doesn't reduce cost (you still pay per metric, not per data point), but reduces agent CPU usage.

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━


## Summary

| Component | Cost |
|-----------|------|
| CloudWatch Agent software | FREE |
| Agent installation | FREE |
| Agent running | FREE |
| Metrics sent by agent | $0.30 per metric/month |
| Logs sent by agent | $0.50/GB ingestion + $0.03/GB storage |

Key Takeaway: The agent itself is free. You only pay for the CloudWatch metrics and logs it generates, which you'd pay for 
anyway if you sent them through other means (SDK, API, etc.).

Typical cost per instance: $10-20/month (depending on log volume)