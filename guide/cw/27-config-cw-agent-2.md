## CloudWatch Agent Configuration for Logs

### Step 1: Update CloudWatch Agent Config

Edit or create: /opt/aws/amazon-cloudwatch-agent/etc/config.json

json
{
  "agent": {
    "run_as_user": "root"
  },
  "logs": {
    "logs_collected": {
      "files": {
        "collect_list": [
          {
            "file_path": "/var/log/app/*.log",
            "log_group_name": "/aws/ec2/app",
            "log_stream_name": "{instance_id}/{local_hostname}",
            "timezone": "UTC",
            "timestamp_format": "%Y-%m-%d %H:%M:%S",
            "multi_line_start_pattern": "{timestamp_format}"
          }
        ]
      }
    }
  }
}


━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━


### Step 2: Apply Configuration

bash
# Stop agent if running
sudo /opt/aws/amazon-cloudwatch-agent/bin/amazon-cloudwatch-agent-ctl \
  -m ec2 \
  -a stop

# Start with new config
sudo /opt/aws/amazon-cloudwatch-agent/bin/amazon-cloudwatch-agent-ctl \
  -a fetch-config \
  -m ec2 \
  -s \
  -c file:/opt/aws/amazon-cloudwatch-agent/etc/config.json

# Check status
sudo /opt/aws/amazon-cloudwatch-agent/bin/amazon-cloudwatch-agent-ctl status


━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━


### Step 3: Verify Logs Are Being Sent

bash
# Check agent logs
sudo tail -f /opt/aws/amazon-cloudwatch-agent/logs/amazon-cloudwatch-agent.log

# Check AWS CloudWatch Logs
aws logs describe-log-streams \
  --log-group-name /aws/ec2/app \
  --order-by LastEventTime \
  --descending \
  --max-items 5


━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━


## Configuration Options Explained

### Multiple Log Files

If you have different log files in /var/log/app/:

json
{
  "logs": {
    "logs_collected": {
      "files": {
        "collect_list": [
          {
            "file_path": "/var/log/app/application.log",
            "log_group_name": "/aws/ec2/app",
            "log_stream_name": "{instance_id}/application.log"
          },
          {
            "file_path": "/var/log/app/error.log",
            "log_group_name": "/aws/ec2/app",
            "log_stream_name": "{instance_id}/error.log"
          },
          {
            "file_path": "/var/log/app/access.log",
            "log_group_name": "/aws/ec2/app",
            "log_stream_name": "{instance_id}/access.log"
          }
        ]
      }
    }
  }
}


━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━


### Separate Log Groups per Log Type

json
{
  "logs": {
    "logs_collected": {
      "files": {
        "collect_list": [
          {
            "file_path": "/var/log/app/application.log",
            "log_group_name": "/aws/ec2/app/application",
            "log_stream_name": "{instance_id}"
          },
          {
            "file_path": "/var/log/app/error.log",
            "log_group_name": "/aws/ec2/app/error",
            "log_stream_name": "{instance_id}"
          }
        ]
      }
    }
  }
}


━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━


### With Log Retention

json
{
  "logs": {
    "logs_collected": {
      "files": {
        "collect_list": [
          {
            "file_path": "/var/log/app/*.log",
            "log_group_name": "/aws/ec2/app",
            "log_stream_name": "{instance_id}/{local_hostname}",
            "retention_in_days": 7
          }
        ]
      }
    },
    "log_stream_name": "{instance_id}"
  }
}


━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━


## Complete Configuration (Logs + Metrics)

json
{
  "agent": {
    "metrics_collection_interval": 60,
    "run_as_user": "root"
  },
  "metrics": {
    "namespace": "MyApp/EC2",
    "metrics_collected": {
      "cpu": {
        "measurement": [
          {"name": "cpu_usage_idle", "rename": "CPU_IDLE", "unit": "Percent"}
        ],
        "metrics_collection_interval": 60
      },
      "mem": {
        "measurement": [
          {"name": "mem_used_percent", "rename": "MEMORY_USED", "unit": "Percent"}
        ],
        "metrics_collection_interval": 60
      },
      "disk": {
        "measurement": [
          {"name": "used_percent", "rename": "DISK_USED", "unit": "Percent"}
        ],
        "metrics_collection_interval": 60,
        "resources": ["*"]
      }
    },
    "append_dimensions": {
      "InstanceId": "${aws:InstanceId}",
      "InstanceType": "${aws:InstanceType}"
    }
  },
  "logs": {
    "logs_collected": {
      "files": {
        "collect_list": [
          {
            "file_path": "/var/log/app/*.log",
            "log_group_name": "/aws/ec2/myapp",
            "log_stream_name": "{instance_id}/{local_hostname}",
            "timezone": "UTC"
          }
        ]
      }
    }
  }
}


━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━


## Test Log Generation

Create test logs to verify:

bash
# Create log directory
sudo mkdir -p /var/log/app

# Generate test logs
echo "$(date) - INFO - Application started" | sudo tee -a /var/log/app/application.log
echo "$(date) - ERROR - Database connection failed" | sudo tee -a /var/log/app/error.log
echo "$(date) - INFO - User logged in" | sudo tee -a /var/log/app/access.log

# Wait 1-2 minutes, then check CloudWatch
aws logs tail /aws/ec2/app --follow


━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━


## Verify in CloudWatch Console

1. Go to CloudWatch Console
2. Navigate to "Logs" → "Log groups"
3. Find /aws/ec2/app
4. Click on log group
5. You should see log streams named like: i-1234567890abcdef0/ip-172-31-1-1

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━


## Cost Estimate

Scenario: 1 EC2 instance, 1 GB logs per day

Component                          Cost
─────────────────────────────────────────
Log ingestion: 30 GB × $0.50       $15.00
Log storage: 30 GB × $0.03         $0.90
─────────────────────────────────────────
TOTAL                              $15.90/month


━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━


## Summary

Configuration file: /opt/aws/amazon-cloudwatch-agent/etc/config.json

Key settings:
- file_path: /var/log/app/*.log (all .log files)
- log_group_name: /aws/ec2/app
- log_stream_name: {instance_id}/{local_hostname}

Commands:
bash
# Restart agent
sudo systemctl restart amazon-cloudwatch-agent

# Check status
sudo systemctl status amazon-cloudwatch-agent

# View agent logs
sudo tail -f /opt/aws/amazon-cloudwatch-agent/logs/amazon-cloudwatch-agent.log